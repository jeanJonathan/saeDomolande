#!/bin/bash

# ================================================================
# Auteur : 
# Date de création : 
# Script Name: ePerfNIC.sh
# Description: This script calculates a PID's NIC power consumption.
# From variables: PID transfer rate and NIC MAX transfer rate
# Usage: ePerfNIC.sh -p PID -t windowTime milliseconds
# Note: A safe windowTime is 100 msecs, otherwise empty values may exist
    #WARN: Lower values make the script calculate low initial values
# Important REFs and values for the NIC: 
  # source to intel confidential (?) sheet specs: 
  #https://www.tonymacx86.com/attachments/cnvi-and-9560ngw-documentation-pdf.342854/
  #https://fccid.io/B94-9560D2WZ/User-Manual/Users-Manual-3800018.pdf

  #Power TpT – 11n HB-40 Rx 11n (at max TpT) 550 mW
  #TpT – 11ac HB-80 Tx 11ac (at max TpT) 1029 mW

  #11ac 160 MHz 2SS Rx Conductive, best attenuation, TCP/IP 1204 Mbps - 150500 KBps
  #11ac 160 MHz 2SS TX Conductive, best attenuation, TCP/IP 1220 Mbps - 152500 KBps
# NIC_INFO: the intel 6 AX201 has Capabilities: [c8] Power Management version 3 (lspci -v)
#...we can custom it depending on the kernel driver for further optimizations
# ================================================================

pid=0
windowTime=0


# On calcule la fréquence moyenne du processeur en lisant /proc/cpuinfo.
get_process_name() {
    pid=$1
    process_name=$(ps -p $pid -o comm=)
    echo $process_name
}

# Identifie automatiquement l'interface réseau active utilisée par le processus.
getNICInterface() # Cette commande affiche les connexes réseau associées à un processus donné
    # Assurez-vous que netstat est installé
    if ! command -v netstat &> /dev/null; then
        echo "netstat n'est pas installé. Installation en cours..."
        sudo apt-get update && sudo apt-get install -y net-tools
        if [ $? -ne 0 ]; then
            echo "Erreur lors de l'installation de net-tools."
            exit 1
        fi
    fi

    # Obtenez le PID du processus
    local process_pid=$1

    # Vérifiez si le PID est fourni
    if [ -z "$process_pid" ]; then
        echo "PID non fourni pour la fonction getNICInterface."
        return 1
    fi

    # Utilisez netstat pour trouver l'interface réseau utilisée par le processus
    local nic_interface=$(netstat -ie | grep -B1 "$(netstat -tunp | grep $process_pid/ | awk '{print $5}' | cut -d: -f1 | sort | uniq)" | head -n1 | awk '{print $1}')

    # Vérifiez si une interface a été trouvée
    if [ -z "$nic_interface" ]; then
        echo "Aucune interface réseau trouvée pour le PID $process_pid."
        return 1
    else
        echo "Interface réseau trouvée pour le PID $process_pid : $nic_interface"
    fi
}


# Mesure les taux de téléchargement et d'envoi du processus spécifié.
# rmq : nethogs, est un outil de suivi de la consommation de bande passante par processus.
# N.B : aucun de ces outils ne fournit directement le taux de téléchargement et d'envoi pour un PID 
# spécifique de manière simple. Les solutions nécessitent donc un certain niveau de manipulation de données.
getNICUsage() {
    # Assurez-vous que nethogs est installé
    if ! command -v nethogs &> /dev/null; then
        echo "nethogs n'est pas installé. Installation en cours..."
        sudo apt-get update && sudo apt-get install -y nethogs
        if [ $? -ne 0 ]; then
            echo "Erreur lors de l'installation de nethogs."
            exit 1
        fi
    fi

    # Obtenez le PID du processus
    local process_pid=$1

    # Vérifiez si le PID est fourni
    if [ -z "$process_pid" ]; then
        echo "PID non fourni pour la fonction getNICUsage."
        return 1
    fi

    # Utilisez nethogs pour capturer le trafic réseau du processus
    nethogs_output=$(timeout 5 sudo nethogs -t -c 10 | grep $process_pid)

    # Extraire les taux de téléchargement et d'envoi
    download_rate=$(echo "$nethogs_output" | awk '{print $2}')
    upload_rate=$(echo "$nethogs_output" | awk '{print $3}')

    # Affichez les résultats
    echo "Taux de téléchargement pour le PID $process_pid : $download_rate KBps"
    echo "Taux d'envoi pour le PID $process_pid : $upload_rate KBps"
}

# Calcule l'énergie consommée par la NIC sur la période spécifiée.
calculateNICEnergy() {
    # Puissance moyenne consommée par la NIC en milliwatts (mW)
    local nic_power_avg=$1

    # Durée pendant laquelle la puissance est consommée en millisecondes (ms)
    local time_period_ms=$2

    # Vérifiez si la puissance et le temps sont fournis
    if [ -z "$nic_power_avg" ] || [ -z "$time_period_ms" ]; then
        echo "La puissance moyenne et/ou la période de temps ne sont pas fournis."
        return 1
    fi

    # Conversion de la période de temps en secondes (1 seconde = 1000 millisecondes)
    local time_period_s=$(echo "scale=3; $time_period_ms / 1000" | bc)

    # Calcul de l'énergie en joules (1 watt = 1 joule par seconde; 1 mW = 0.001 watts)
    local nic_energy=$(echo "scale=3; $nic_power_avg * 0.001 * $time_period_s" | bc)

    echo "Énergie consommée par la NIC : $nic_energy joules"
}

# Récupère les spécifications de la carte réseau (puissance et taux de transfert max).
getNICSpecifications() {
    # Utilisation de lshw pour obtenir des informations sur la carte réseau
    nic_info=$(sudo lshw -class network)

    # Vérification si lshw a fourni les informations nécessaires
    if [ -n "$nic_info" ]; then
        echo "Informations NIC trouvées avec lshw:"
        echo "$nic_info"
        return 0
    fi

    # Utilisation de lspci pour obtenir des informations sur la carte réseau
    nic_info=$(sudo lspci | grep -i network)

    # Vérification si lspci a fourni les informations nécessaires
    if [ -n "$nic_info" ]; then
        echo "Informations NIC trouvées avec lspci:"
        echo "$nic_info"
        return 0
    fi

    # Utilisation de ethtool pour obtenir des informations sur les capacités de la carte réseau
    nic_interfaces=$(ip link show | awk -F: '$0 !~ "lo|vir|^[^0-9]"{print $2;getline}')
    for iface in $nic_interfaces; do
        nic_info=$(ethtool $iface)
        if [ -n "$nic_info" ]; then
            echo "Informations NIC pour l'interface $iface trouvées avec ethtool:"
            echo "$nic_info"
        fi
    done

    # Utilisation de rfkill pour obtenir des informations sur les dispositifs sans fil
    rfkill_info=$(rfkill list)
    if [ -n "$rfkill_info" ]; then
        echo "Informations sur les dispositifs sans fil trouvées avec rfkill:"
        echo "$rfkill_info"
    fi
}


#Fonction pour gerer les options de la ligne de commande duree de surveillance avec wnidowTime par exp
getInput() {
    while getopts "t:p:" opt; do
        case ${opt} in
            t ) windowTime=$OPTARG ;;
            p ) pid=$OPTARG ;;
            \? ) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
            : ) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
        esac
    done
}


#Fonction pour calculer la consommation d'énergie du processus spécifié en multipliant l'utilisation du CPU, 
#la fréquence et la tension, puis en moyennant ces valeurs sur la période spécifiée 

getNICCons() {
    # Récupération du nom du processus
    process_name=$(get_process_name $pid)

    # Identification de l'interface réseau utilisée par le processus
    nic_interface=$(getNICInterface $pid)
    if [ -z "$nic_interface" ]; then
        echo "Aucune interface réseau trouvée pour le PID $pid."
        # Si l'interface réseau n'est pas trouvée, on termine la fonction
        return 1
    fi

    # Récupération des taux de téléchargement et d'envoi du processus spécifié
    getNICUsage $pid
    if [ -z "$download_rate" ] || [ -z "$upload_rate" ]; then
        echo "Taux de téléchargement et d'envoi non disponibles pour le PID $pid."
        return 1
    fi

    # Récupération des taux de téléchargement et d'envoi
    getNICUsage $pid
    upload_rate_avg=$upload_rate
    download_rate_avg=$download_rate

    # Récupération des spécifications de la carte réseau
    getNICSpecifications
    # Les variables 'max_download_power', 'max_upload_power', 'max_download_rate', 'max_upload_rate' sont définies ici

    # Calcul de la puissance consommée par la NIC pour le téléchargement et l'envoi
    
    upload_power=$(echo "scale=10; $max_upload_power * ($upload_rate_avg / $max_upload_rate)" | bc)
    download_power=$(echo "scale=10; $max_download_power * ($download_rate_avg / $max_download_rate)" | bc)

    # Calcul de la puissance moyenne consommée par la NIC
    nic_power_avg=$(echo "scale=10; ($upload_power + $download_power) / 2" | bc)

    # Calcul de l'énergie consommée par la NIC
    nic_energy=$(calculateNICEnergy $nic_power_avg $windowTime)

    # Vérifiez si la fonction calculateNICEnergy a réussi
    if [ -z "$nic_energy" ]; then
        echo "Erreur lors du calcul de l'énergie consommée par la NIC."
        return 1
    fi

    # Affichage des résultats
    echo "Processus: $process_name"
    echo "Interface NIC: $nic_interface"
    echo "Taux de téléchargement moyen: $download_rate_avg KBps"
    echo "Taux d'envoi moyen: $upload_rate_avg KBps"
    echo "Puissance moyenne consommée par la NIC : $nic_power_avg mW"
    echo "Énergie consommée par la NIC : $nic_energy joules"
}

#Fonction pour verifier et valider les entrees de windowTime et pid
verifyInput() {
    if [ $windowTime -lt 100 ]; then
        echo "I need a bigger windowTime :(..."; exit
    fi
    if [ ! -e "/proc/$pid/stat" ]; then
        echo "Non-existent PID"; exit
    fi
}


#Fonction pour Afficher l'énergie consommée et la puissance moyenne
verifyPrintOutput()
{   #verify if it's a non empty numerical value  
  if [[ ! -z $nic_energy ]] && \
     [[ $nic_energy =~ ^[0-9]*([.][0-9]+)?$ ]] && \
     [[ ! -z $nic_power_AVG ]] && \
     [[ $nic_power_AVG =~ ^[0-9]*([.][0-9]+)?$ ]]; then

        echo nic_energy_J: $nic_energy
        echo nic_avgPower_W: $nic_power_AVG
  else
        echo error somewhere
    fi
}
# Orchestre l'exécution des méthodes pour le calcul de la consommation d'énergie.
main() {
    getInput "$@"
    verifyInput
    getCPUCons
    verifyPrintOutput
}
