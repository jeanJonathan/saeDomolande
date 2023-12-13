#!/bin/bash

# ================================================================
# Auteur : jean-jonathan K
# Date de création : 4/12/2023
# 
# Description :
# Ce script est conçu pour mesurer la consommation d'énergie 
# et la puissance moyenne du CPU d'un processus spécifique sur la distribution 
# Unbutu de Linux. Il utilise des informations sur la fréquence, la tension 
# du CPU et l'utilisation du CPU pour calculer ces mesures.
#
# Utilisation :
# ./ePerfCPU.sh -p [PID du processus] -t [Durée fenêtre de surveillance en millisecondes]
# Exemple : ./ePerfCPU.sh -p 1234 -t 1000
#
# Remarques :
# Assurez-vous que le module 'msr' est chargé pour lire les registres MSR.
# Le script nécessite des privilèges sudo pour accéder à certains registres.
#
# Quel ques liens sources : 
# Surveillance de l'utilisation du CPU : https://linuxconfig.org/bash-script-to-monitor-cpu-and-memory-usage-on-linux
#https://unix.stackexchange.com/questions/69167/bash-script-that-print-cpu-usage-diskusage-ram-usage
#Lecture et écriture des registres MSR spécifiques au modèle : https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/best-practices/reading-writing-msrs-in-linux.html#:~:text=Model,or%20toggling%20specific%20CPU%20features
https://www.man7.org/linux/man-pages/man4/msr.4.html#:~:text=DESCRIPTION%20top%20%2Fdev%2Fcpu%2FCPUNUM%2Fmsr%20provides%20an,as%20listed%20in%20%2Fproc%2Fcpuinfo
https://linux.die.net/man/4/msr
#Gestion et surveillance de la consommation d'énergie: https://linuxconfig.org/how-to-check-and-tune-power-consumption-with-powertop-on-linux
#Participation à amélioration de ce script : https://chat.openai.com/
#================================================================


pid=0
windowTime=0

cpu_energy=0
cpu_power_AVG=0

# On calcule la fréquence moyenne du processeur en lisant /proc/cpuinfo.
get_cpu_frequency() {
    awk '/cpu MHz/ {freq_sum += $4; count++} END {print freq_sum / count / 1000}' /proc/cpuinfo
}

#Fonction qui lit et reccupere la tension du processeur à partir des registres MSR 
get_cpu_voltage() {
    # On s'assure d'abord que le module 'msr' est chargé
    if ! lsmod | grep -q msr; then
        echo "Le module MSR n'est pas chargé. Exécutez 'sudo modprobe msr'."
        return 1
    fi

    # On lire la tension à partir des registres MSR
    # Rmq: l'adresse du registre MSR peut varier selon le processeur
    local msr_voltage
    msr_voltage=$(sudo rdmsr -f 47:32 -d 0x198)

    # Conversion en volts
    local voltage
    voltage=$(echo "scale=3; $msr_voltage / 8192" | bc)

    # On ajoute un zéro devant si le nombre commence par un point car la syntaxe bash par defaut pour les decimaux est .8 pour 0.8
    if [[ $voltage == .* ]]; then
        voltage="0$voltage"
    fi

    echo $voltage
}

#Fonction qui Récupère le pourcentage d'utilisation du CPU pour le processus spécifié par son PID 
get_cpu_usage() {
    #on retourne la premiere valeur de l'utilisation pour le thread actif
    ps -L -p "$pid" -o pcpu --no-headers | awk '$1 > 0 {print $1; exit}'
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
getCPUCons() {
    cpu_freq=$(get_cpu_frequency)
    cpu_voltage=$(get_cpu_voltage)

    echo "Frequency: $cpu_freq GHz. Voltage: $cpu_voltage V"

    if [ -z "$cpu_freq" ] || [ -z "$cpu_voltage" ] || [ "$cpu_voltage" == "N/A" ]; then
        echo "Error in fetching CPU frequency or voltage"; exit 1
    fi

    accumulated_PID_power=0
    counter=0
    end=$(($(date +%s%N)+windowTime*1000000))

    while [ $(date +%s%N) -lt $end ]; do
        cpu_usage=$(get_cpu_usage)
        echo "CPU Usage: $cpu_usage %"

        if [[ $cpu_usage != "0" ]]; then
            total_PID_power=$(echo "scale=10; $cpu_usage * $cpu_freq * $cpu_voltage" | sed 's/,/./g' | bc -l)
    
	    if [[ $total_PID_power == .* ]]; then
		total_PID_power="0$total_PID_power"
	    fi
            echo "Total PID Power: $total_PID_power W"

            if [ -z "$total_PID_power" ]; then
                echo "Error in calculating power"; exit 1
            fi

            accumulated_PID_power=$(echo "scale=10; $accumulated_PID_power + $total_PID_power" | bc -l)
        fi
        counter=$((counter + 1))
        sleep 0.1
    done

    if [ $counter -eq 0 ]; then
        echo "No CPU usage data was gathered"; exit 1
    fi

    cpu_power_AVG=$(echo "scale=10; $accumulated_PID_power / $counter" | bc -l)
    cpu_energy=$(echo "scale=10; $cpu_power_AVG * $windowTime * 0.001" | bc -l)
    
    if [[ $cpu_power_AVG == .* ]]; then
	  cpu_power_AVG="0$cpu_power_AVG"
    fi

    if [[ $cpu_energy == .* ]]; then
	cpu_energy="0$cpu_energy"
    fi	

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
verifyPrintOutput() {
    if [[ ! -z $cpu_energy ]] && [[ $cpu_energy =~ ^[0-9]*([.][0-9]+)?$ ]] && [[ ! -z $cpu_power_AVG ]] && [[ $cpu_power_AVG =~ ^[0-9]*([.][0-9]+)?$ ]]; then
        echo "cpu_energy_J: $cpu_energy J"
        echo "cpu_avgPower_W: $cpu_power_AVG W"
    else
        echo "error somewhere"
    fi
}

main() {
    getInput "$@"
    verifyInput
    getCPUCons
    verifyPrintOutput
}

main "$@"
