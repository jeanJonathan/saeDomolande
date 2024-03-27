#!/bin/bash

# ================================================================
# Auteur : jean-jonathan K
# Date de création : 4/12/2023
# 
# Description :
# Ce script est conçu pour mesurer en continu la consommation d'énergie et la puissance moyenne du CPU, ainsi que la consommation de RAM, d'un processus spécifique sur Ubuntu. Il utilise des données en temps réel telles que la fréquence, la tension et l'utilisation du CPU pour fournir une estimation précise de la consommation d'énergie. De plus, il communique avec le script floc.sh pour une surveillance continue des processus en cours d'exécution.
#
# Remarques :
# - Assurez-vous que le module 'msr' est chargé pour lire les registres MSR.
# - Le script nécessite des privilèges sudo pour accéder à certains registres.
#
# Quelques liens sources :
# Surveillance de l'utilisation du CPU : https://linuxconfig.org/bash-script-to-monitor-cpu-and-memory-usage-on-linux
# https://unix.stackexchange.com/questions/69167/bash-script-that-print-cpu-usage-diskusage-ram-usage
# Lecture et écriture des registres MSR spécifiques au modèle : https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/best-practices/reading-writing-msrs-in-linux.html#:~:text=Model,or%20toggling%20specific%20CPU%20features
# https://www.man7.org/linux/man-pages/man4/msr.4.html#:~:text=DESCRIPTION%20top%20%2Fdev%2Fcpu%2FCPUNUM%2Fmsr%20provides%20an,as%20listed%20in%20%2Fproc%2Fcpuinfo
# https://linux.die.net/man/4/msr
# Gestion et surveillance de la consommation d'énergie : https://linuxconfig.org/how-to-check-and-tune-power-consumption-with-powertop-on-linux
# Thermal Design Power (TDP) : https://www.intel.com/content/www/us/en/developer/overview.html
# Utilisation de powercap-info pour les processeurs Intel : https://www.cnx-software.com/2022/09/08/how-to-check-tdp-pl1-and-pl2-power-limits-in-windows-and-linux/
# Participation à l'amélioration de ce script : https://chat.openai.com/
# =================================================================


pid=0
windowTime=1000 # valeur de mesure par defaut

cpu_energy=0
cpu_power_AVG=0
ram_energy=0
ram_power_AVG=0

# On calcule la fréquence moyenne du processeur en lisant /proc/cpuinfo.

get_process_name() {
    pid=$1
    process_name=$(ps -p $pid -o comm=)
    echo $process_name
}

get_cpu_name() {
    cat /proc/cpuinfo | grep "model name" | head -1 | awk -F ': ' '{print $2}'
}

get_cpu_frequency() {
    # Utiliser awk avec LC_NUMERIC=C pour s'assurer que le point est utilisé comme séparateur décimal
    freq=$(LC_NUMERIC=C awk '/cpu MHz/ {freq_sum += $4; count++} END {print freq_sum / count / 1000}' /proc/cpuinfo)
    echo $freq
}

#Fonction qui lit et reccupere la tension du processeur à partir des registres MSR 
#en faisant une mesure dynamique de la tension, qui varie en fonction de la charge actuelle du processeur
#pour une mesure statique : sudo dmidecode -t processor (pour obtenir spécification standard du fabriquant)

get_cpu_voltage() {
    # Vérifier si les msr-tools sont installées. Si non, les installer.
    if ! command -v rdmsr &> /dev/null; then
        echo "msr-tools n'est pas installé. Installation en cours..."
        sudo apt-get update && sudo apt-get install -y msr-tools
        if [ $? -ne 0 ]; then
            echo "Erreur lors de l'installation des msr-tools. Assurez-vous que votre système peut les installer."
            return 1
        fi
    fi

    # On s'assure d'abord que le module 'msr' est chargé
    if ! lsmod | grep -q msr; then
        echo "Le module MSR n'est pas chargé. Exécutez 'sudo modprobe msr'."
        return 1
    fi

    # Lire la tension à partir des registres MSR
    msr_voltage=$(sudo rdmsr -f 47:32 -d 0x198)

    # Conversion en volts
    voltage=$(echo "scale=3; $msr_voltage / 8192" | bc)

    # Ajouter un zéro devant si le nombre commence par un point
    if [[ $voltage == .* ]]; then
        voltage="0$voltage"
    fi

    echo $voltage
}

#Fonction qui Récupère le pourcentage d'utilisation du CPU pour le processus spécifié par son PID 
get_cpu_usage() {
    if [ -z "$pid" ]; then
        echo "PID is required"
        return 1
    fi

    stat_file="/proc/$pid/stat"
    if [ ! -f "$stat_file" ]; then
        echo "Process with PID $pid not found"
        return 1
    fi

    # On obtient la valeur de HZ
    hz=$(getconf CLK_TCK)

    # Lecture initiale des temps CPU
    stat_content1=$(<"$stat_file")
    utime1=$(echo "$stat_content1" | awk '{print $14}')
    stime1=$(echo "$stat_content1" | awk '{print $15}')

    # Attente de la durée spécifiée
    sleep $((windowTime / 1000))

    # Lecture finale des temps CPU
    stat_content2=$(<"$stat_file")
    utime2=$(echo "$stat_content2" | awk '{print $14}')
    stime2=$(echo "$stat_content2" | awk '{print $15}')

    # Calcul de l'utilisation du CPU
    cpu_usage=$((utime2 + stime2 - utime1 - stime1))
    cpu_usage_seconds=$(echo "scale=2; $cpu_usage / $hz" | bc)
    cpu_usage_percentage=$(echo "scale=2; $cpu_usage_seconds / ($windowTime / 1000) * 100" | bc)

    echo "$cpu_usage_percentage"
}

# Fonction pour obtenir le TDP, indicateur de la capacité maximale
# de dissipation thermique du CPU
get_cpu_tdp() {
    cpu_name="$1"
    
    # On vérifie si le CPU est un modèle Intel
    if [[ $cpu_name == *"Intel"* ]]; then
        # On vérifie si powercap-info est installé, sinon on installe
        if ! command -v powercap-info &> /dev/null; then
            echo "Installing powercap-info..."
            sudo apt install powercap-utils -y
        fi

        # Exécute powercap-info pour obtenir les limites de puissance du CPU
        # et sélectionne la première limite de puissance à long terme (PL1), 
        # qui est souvent proche de la valeur du TDP
        tdp_data=$(powercap-info -p intel-rapl | grep "power_limit_uw" | head -1 | awk '{print $2}')
        # Convertit la valeur de micro-watts en watts
        tdp_watts=$(echo "$tdp_data" | awk '{print $1/1000000}')
        echo $tdp_watts 
    elif [[ $cpu_name == *"AMD"* ]]; then
        # Placeholder pour les CPU AMD - à voir plustard...
        echo "AMD CPU detected -"
    else
        # Placeholder pour les autres types de CPU...
        echo "Other CPU detected -"
    fi
}

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

# Exécution de la commande perf et extraction des données
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
        echo "Ajustement automatique de perf_event_paranoid pour permettre le monitoring détaillé."
        echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null
        
        # Enregistrer une commande trap pour restaurer la valeur originale à la sortie du script
        trap "echo 'Restauration de perf_event_paranoid à sa valeur originale : $original_paranoid_level.'; echo $original_paranoid_level | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null" EXIT
    fi

    # Exécution de perf et extraction des données
    perf_output=$(perf stat -e mem-stores,mem-loads -p $pid --timeout=$windowTime 2>&1)

    mem_stores=$(echo "$perf_output" | grep 'mem-stores' | awk '{print $1}' | sed 's/[^0-9]//g')
    mem_loads=$(echo "$perf_output" | grep 'mem-loads' | awk '{print $1}' | sed 's/[^0-9]//g')

    if [[ -z $mem_stores || -z $mem_loads ]]; then
    	echo "Erreur : Données 'perf' de store/load mémoire non capturées. Cela peut être dû à un accès concurrent aux ressources. Essayez d'augmenter 'windowTime' et de minimiser la charge système si celle du cpu est trop elevee."
    	return 1
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
getCPUCons() {
    cpu_freq=$(get_cpu_frequency)
    cpu_voltage=$(get_cpu_voltage) 
    
    #On precise le nom du cpu pour obtenir la capacite tdp   
    cpu_capacity=$(get_cpu_tdp "$cpu_name")
    echo "frequency: $cpu_freq GHz. voltage: $cpu_voltage V . capacity $cpu_capacity ≈W"

    
    if [ -z "$cpu_freq" ] || [ -z "$cpu_voltage" ] || [ "$cpu_voltage" == "N/A" ]; then
        echo "Error in fetching CPU frequency or voltage"; exit 1
    fi

    accumulated_PID_power=0
    counter=0
    end=$(($(date +%s%N)+windowTime*1000000))

    while [ $(date +%s%N) -lt $end ]; do
        cpu_usage=$(get_cpu_usage)
        echo "%cpu usage by process: $cpu_usage"

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

getRAMCons() {
    # Récupération du nom du processus et de l'utilisation de la RAM
    get_ram_usage
    get_io_operations
    execute_perf
    
    # Assurez-vous que nous avons des valeurs valides avant de calculer.
    if [[ -z $mem_stores || -z $mem_loads ]]; then
        echo "Erreur : Les valeurs de store/load sont vides."
        return 1
    fi
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

# Fonction pour surveiller et calculer continuellement la consommation d'énergie et la puissance du CPU
monitor_and_calculate_energy_continuously() {
    cpu_name=$(get_cpu_name)
    process_name=$(get_process_name $pid)
    total_energy_accumulated=0 # Initialisation de l'accumulateur d'énergie totale pour toutes les mesures

    # Définition de quelques couleurs
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # Pas de Couleur

    echo -e "${GREEN}CPU detected: ${NC}$cpu_name"
    echo -e "${GREEN}process detected: ${NC}$process_name"
    while [ -e "/proc/$pid" ]; do
        echo ""
        echo -e "${YELLOW}Timestamp: ${NC}$(date '+%Y-%m-%d %H:%M:%S')"
        getCPUCons
        getRAMCons

        verifyPrintOutputCPU
        verifyPrintOutputRAM
        # Calcul et affichage de l'énergie totale pour cette mesure
        total_energy_this_measure=$(echo "scale=10; $cpu_energy + $ram_energy" | bc)
        # Utilisation de LC_NUMERIC=C pour s'assurer que le format de nombre utilise un point
        formatted_energy_this_measure=$(LC_NUMERIC=C printf "%.10f\n" $total_energy_this_measure)
        echo -e "${BLUE}Énergie totale pour cette mesure (CPU + RAM) : ${NC}$formatted_energy_this_measure J"
        # Accumulation de l'énergie totale
        total_energy_accumulated=$(echo "scale=10; $total_energy_accumulated + $total_energy_this_measure" | bc)

        sleep $((windowTime / 500)) # Pause entre les mesures
    done

    # Formatage de l'énergie totale accumulée à l'arrêt du programme
    formatted_total_energy=$(LC_NUMERIC=C printf "%.10f\n" $total_energy_accumulated)
    echo -e "${RED}Énergie totale consommée pendant l'exécution (CPU + RAM) : ${NC}$formatted_total_energy J"
    echo -e "${RED}Le processus $pid a terminé son exécution.${NC}"
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
verifyPrintOutputCPU() {
    RED='\033[0;31m'
    NC='\033[0m' # Pas de Couleur
    if [[ ! -z $cpu_energy ]] && [[ $cpu_energy =~ ^[0-9]*([.][0-9]+)?$ ]] && [[ ! -z $cpu_power_AVG ]] && [[ $cpu_power_AVG =~ ^[0-9]*([.][0-9]+)?$ ]]; then
        echo -e "${RED}cpu_energy_J: ${NC}$cpu_energy J"
        echo -e "${RED}cpu_avgPower_W: ${NC}$cpu_power_AVG W"
    else
        echo -e "${RED}error somewhere${NC}"
    fi
}

verifyPrintOutputRAM() {
    RED='\033[0;31m'
    NC='\033[0m' # Pas de Couleur
    if [[ ! -z $ram_energy ]] && [[ $ram_energy =~ ^[0-9]*([.][0-9]+)?$ ]] && [[ ! -z $ram_power_AVG ]] && [[ $ram_power_AVG =~ ^[0-9]*([.][0-9]+)?$ ]]; then
        echo -e "${RED}ram_energy_J: ${NC}$ram_energy J"
        echo -e "${RED}ram_avgPower_W: ${NC}$ram_power_AVG W"
    else
        echo -e "${RED}error somewhere${NC}"
    fi
}


main() {
    getInput "$@"
    verifyInput
    monitor_and_calculate_energy_continuously
}

main "$@"

