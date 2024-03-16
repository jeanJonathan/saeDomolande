#!/bin/bash

# ================================================================
# Auteur : jean-jonathan K
# Date de création : 20/12/2023
# 
# Description :
#Ce script est conçu pour mesurer la consommation d'énergie et la puissance moyenne de la RAM utilisée par un processus spécifique sur Ubuntu. 
#Il collecte des données telles que l'utilisation de la mémoire, les opérations de lecture et 
#d'écriture, et utilise les événements de performance (perf) pour calculer l'énergie et la puissance.
#Remarque : Les événements perf sont différents pour chaque architecture de CPU
#Remarque : Un windowTime sûr est de 100 ms, sinon des valeurs vides peuvent exister
#
# ================================================================

# Initialisation des variables
pid=0
windowTime=0

ram_energy=0
ram_power_AVG=0

get_process_name() {
    process_name=$(ps -p $pid -o comm=)
    echo "Process name: $process_name"
}

get_ram_usage() {
    mem_usage=$(grep VmRSS /proc/$pid/status | awk '{print $2}')
    echo "RAM usage (VmRSS): $mem_usage KB"
}

get_io_operations() {
    io_read=$(grep read_bytes /proc/$pid/io | awk '{print $2}')
    io_write=$(grep write_bytes /proc/$pid/io | awk '{print $2}')
    echo "I/O Read: $io_read bytes, I/O Write: $io_write bytes"
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

# Fonctino pour exécution de la commande perf et extraction des données
execute_perf() {

    # Vérification de l'installation de perf
    if ! command -v perf &> /dev/null; then
        echo "perf n'est pas installé. Veuillez exécuter :"
        echo "sudo apt-get install linux-tools-common linux-tools-generic linux-tools-$(uname -r)"
        exit 1
    fi

    # Vérification et ajustement de perf_event_paranoid
    original_paranoid_level=$(cat /proc/sys/kernel/perf_event_paranoid)
    if [[ $original_paranoid_level -gt -1 ]]; then
        echo "Ajustement nécessaire de perf_event_paranoid (valeur actuelle : $original_paranoid_level)."
        echo "Exécution : echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid"
        echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
        echo "ATTENTION : Restaurez le niveau de sécurité original après utilisation :"
        echo "echo $original_paranoid_level | sudo tee /proc/sys/kernel/perf_event_paranoid"
    fi

    # Exécution de perf et extraction des données
    perf_output=$(perf stat -e mem-stores,mem-loads -p $pid --timeout=$windowTime 2>&1)

    mem_stores=$(echo "$perf_output" | grep 'mem-stores' | awk '{print $1}' | sed 's/[^0-9]//g')
    mem_loads=$(echo "$perf_output" | grep 'mem-loads' | awk '{print $1}' | sed 's/[^0-9]//g')

    if [[ -z $mem_stores || -z $mem_loads ]]; then
        echo "Error: Unable to get memory store/load data from perf"
        return 1
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

getRAMCons() {
    # Récupération du nom du processus et de l'utilisation de la RAM
    get_process_name
    get_ram_usage
    get_io_operations
    execute_perf
    # Calcul de l'énergie et de la puissance moyenne de la RAM
    ram_act=$(echo "scale=10; ($mem_loads * 6.6) + ($mem_stores * 8.7)" | bc) # nanoJoules
    ram_energy=$(echo "scale=10; $ram_act / 1000000000" | bc) # Conversion en Joules
    if [[ $windowTime -gt 0 ]]; then
        ram_power_AVG=$(echo "scale=10; $ram_energy / ($windowTime * 0.001)" | bc)
    else
        echo "Error: Invalid windowTime."
        return 1
    fi

    if [[ $ram_energy  == .* ]]; then
        ram_energy="0$ram_energy"
    fi
    if [[ $ram_power_AVG  == .* ]]; then
        ram_power_AVG="0$ram_power_AVG"
    fi
    # Restauration de perf_event_paranoid à sa valeur d'origine à la fin du script
    trap "echo $original_paranoid_level | sudo tee /proc/sys/kernel/perf_event_paranoid > /dev/null" EXIT
}

#Fonction pour Afficher l'énergie consommée et la puissance moyenne
verifyPrintOutput() {
    if [[ ! -z $ram_energy ]] && [[ $ram_energy =~ ^[0-9]*([.][0-9]+)?$ ]] && [[ ! -z $ram_power_AVG ]] && [[ $ram_power_AVG =~ ^[0-9]*([.][0-9]+)?$ ]]; then
        echo "ram_energy_J: $ram_energy J"
        echo "ram_avgPower_W: $ram_power_AVG W"
    else
        echo "error somewhere"
    fi
   
}

main()
{
  getInput "$@"
  verifyInput
  getRAMCons
  verifyPrintOutput
}

main "$@"
