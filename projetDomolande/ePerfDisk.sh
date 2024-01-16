#!/bin/bash

# ================================================================
# Auteur : Noah Gomes
# Date de création : 22/12/2023
# 
# Description :
# Ce script est conçu pour mesurer la consommation d'énergie du disque sur Ubuntu. 
# Il utilise des données en temps réel comme le taux de transfert, le temps d'utilisation,
# et la puissance du disque pour fournir une estimation précise.
# ./ePerfDisk.sh -d [Nom du périphérique de disque] -t [Durée fenêtre de surveillance en secondes]
# Exemple: ./ePerfDisk.sh -d sda -t 60
#
# Remarques :
# Le script nécessite des privilèges sudo pour accéder à certaines informations.
#
# Quelques liens sources : 
# Utilisation de iostat pour surveiller le disque : https://www.tecmint.com/iostat-monitor-linux-system-activity-performance/
# Calcul de la consommation d'énergie avec Powertop : https://unix.stackexchange.com/questions/1406/is-there-a-tool-that-can-provide-gui-i-e-visual-power-usage-reports-for-ubuntu
# Gestion et surveillance de la consommation d'énergie : https://linuxconfig.org/how-to-check-and-tune-power-consumption-with-powertop-on-linux
#================================================================
sudo hdparm -I /dev/sda

device=""
windowTime=0

disk_energy=0
disk_power_AVG=0

# Fonction qui récupère le nom du disque en fonction du périphérique
get_disk_name() {
    device=$1
    disk_name=$(lsblk -no MODEL /dev/"$device")
    echo $disk_name
}

# Fonction qui récupère le taux de transfert du disque en KB/s
get_disk_transfer_rate() {
    device=$1
    iostat_result=$(iostat -d -k -x "$device" 1 2 | awk '{if(NR==7) print $4}')
    echo $iostat_result
}

# Fonction qui récupère la puissance du disque en Watts
get_disk_power() {
    # Placeholder - adapt this based on your system's capabilities or use external tools
    # For demonstration purposes, we assume a constant power value.
    echo "7"
}

# Fonction qui calcule la consommation d'énergie du disque
get_disk_energy() {
    transfer_rate=$(get_disk_transfer_rate $device)
    power=$(get_disk_power)

    if [ -z "$transfer_rate" ] || [ -z "$power" ]; then
        echo "Error in fetching disk transfer rate or power"; exit 1
    fi

    disk_energy=$(echo "scale=10; $transfer_rate * $power * $windowTime / 3600" | bc -l)

    if [[ $disk_energy == .* ]]; then
        disk_energy="0$disk_energy"
    fi

    echo "$disk_energy"
}

# Fonction pour gérer les options de la ligne de commande (périphérique de disque et durée de surveillance)
getInput() {
    while getopts "d:t:" opt; do
        case ${opt} in
            d ) device=$OPTARG ;;
            t ) windowTime=$OPTARG ;;
            \? ) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
            : ) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
        esac
    done
}

# Fonction pour vérifier et valider les entrées (périphérique de disque et durée de surveillance)
verifyInput() {
    if [ -z "$device" ]; then
        echo "Device name is required"; exit 1
    fi
    if [ $windowTime -le 0 ]; then
        echo "Invalid windowTime"; exit 1
    fi
}

# Fonction pour afficher l'énergie consommée et la puissance moyenne du disque
verifyPrintOutput() {
    if [[ ! -z $disk_energy ]] && [[ $disk_energy =~ ^[0-9]*([.][0-9]+)?$ ]]; then
        # Conversion de l'énergie en Watts
        energy_watts=$(echo "scale=10; $disk_energy / $windowTime" | bc -l)
        
        if [[ $energy_watts == .* ]]; then
            energy_watts="0$energy_watts"
        fi

        echo "disk_energy_W: $energy_watts W"
    else
        echo "Error in calculating disk energy"; exit 1
    fi
}


# Fonction principale
main() {
    getInput "$@"
    verifyInput
    disk_name=$(get_disk_name $device)
    echo "Disk detected: $disk_name"
    get_disk_energy
    verifyPrintOutput
}

# Appel de la fonction principale avec les arguments de la ligne de commande
main "$@"
#Eexcute la fonction en prenant en argument une conso fixe de disque et calculant sa conso energetique
