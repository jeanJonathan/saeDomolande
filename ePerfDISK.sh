#!/bin/bash

# Configuration de trap pour appeler force_stop lors de la réception de SIGINT
trap force_stop SIGINT
stop=false


# Initialisation des totaux cumulatifs
total_write_energy_cumulative=0
total_read_energy_cumulative=0
total_read_bytes_cumulative=0
total_write_bytes_cumulative=0
total_energy_cumulative=0


# Function to check if the process is running and get its PID
check_process_running() {
    
    while true; do
        # Utiliser pgrep pour trouver le PID du processus par son nom
        pid_pere=$(pgrep "$processName")

        if [ -n "$pid_pere" ]; then
            pids=$(pgrep -f "$processName")
            echo "Le processus '$processName' a démarré avec le PID $pid_pere."
            break  # Sortir de la boucle si le processus est trouvé
        else
            echo "Le processus '$processName' n'est pas encore démarré. Réessai dans $interval secondes..."
            sleep "$interval"
        fi
    done

    
    
}

force_stop(){
    stop=true
}

# Fonction pour vérifier si le processus avec le PID spécifié est en cours d'exécution
is_process_running() {
    ps -p $1 > /dev/null 2>&1
    return $?
}



# Fonction pour collecter les données
data_collect() {
    # Capture du temps de début
        start_time=$(date +%s)
        # Convertir la chaîne de PIDs en tableau

pid_array=($pids)
# Boucle tant qu'il y a des PIDs dans le tableau
while [ ${#pid_array[@]} -gt 0 ]; do
    

   for pid in "${pid_array[@]}"; do # Utiliser l'index pour pouvoir supprimer des éléments

        if is_process_running "$pid"; then
           # echo "Traitement du PID: $pid"
            rawOutputFile="disk_raw_$pid.txt"
            rm -f "$rawOutputFile"
           # echo "Le programme est en cours d'exécution pour le PID $pid..."

            # Capture des données d'E/S du disque pour le PID spécifié
            sudo cat /proc/"$pid"/io > "$rawOutputFile"

        else
            #echo "Le processus avec le PID $pid n'est plus en cours d'exécution."

            # Capture du temps de fin et calcul de la durée
            end_time=$(date +%s)
            duration=$((end_time - start_time))


            # Calculer l'énergie consommée par les opérations d'E/S du disque
            calculateDISKEnergy "$pid"

           

            # Supprimer le PID du tableau
            unset 'pid_array[pid]'
        fi
    done


    if ! pgrep "$processName" > /dev/null; then
     #  echo "Aucun processus père détécté, la mesure s'arrête"

    break

    fi
    
    if  $stop; then
    calculateDISKEnergy "$pid"

    break

    fi

   # Vérifier si tous les processus ont terminé
    if [ ${#pid_array[@]} -eq 0 ]; then
       # echo "Tous les processus spécifiés ont terminé."
        break  # Sortir de la boucle while
    fi

    

    # Attente pour l'intervalle spécifié avant la prochaine itération
    sleep "$interval"
done
total_energy_cumulative_watt=$(echo "scale=10; $total_energy_cumulative / $duration " | bc)
  echo "Le tracking total a duré $duration secondes."
  echo "Total des écritures disque: $total_write_bytes_cumulative Bytes"
    echo "Total des lectures disque: $total_read_bytes_cumulative Bytes"
    echo "Énergie consommée par les écritures disque: $total_write_energy_cumulative J"
    echo "Énergie consommée par les lectures disque: $total_read_energy_cumulative J"
    echo "Énergie totale consommée par les activités disque: $total_energy_cumulative J"
    echo "Énergie totale consommée par les activités disque: $total_energy_cumulative_watt W"
}









# Fonction pour calculer l'énergie consommée par les activités disque
calculateDISKEnergy() {

    if [ ! -f ./nicParam.conf ]; then
    echo "Le fichier de configuration n'a pas été trouvé."
    exit 1
    fi
    source ./nicParam.conf
    # Initialisation des variables pour les lectures et écritures disque
    totalWriteBytes=0
    totalReadBytes=0

    write_power=6.1
    read_power=5.1
    write_max_rate=1600000000
    read_max_rate=2800000000


    # Nom du fichier contenant les données disque
    diskOutputFile="disk_raw_$pid.txt" 

    # Lecture du fichier ligne par ligne
    while IFS= read -r line; do
        case "$line" in
            read_bytes:*) totalReadBytes=$(echo "$line" | awk '{print $2}') ;;
            write_bytes:*) totalWriteBytes=$(echo "$line" | awk '{print $2}') ;;
        esac
    done < "$diskOutputFile"

   
    # Calcul de la puissance moyenne pour les lectures et écritures
    write_power_avg=$(echo "scale=10; $write_power * ($totalWriteBytes / $write_max_rate)" | bc)
    read_power_avg=$(echo "scale=10; $read_power * ($totalReadBytes / $read_max_rate)" | bc)

    # Calcul de l'énergie consommée (en supposant que la durée est en secondes)
    write_energy=$(echo "scale=10; $write_power_avg * $duration" | bc)
    read_energy=$(echo "scale=10; $read_power_avg * $duration" | bc)
    total_energy=$(echo "scale=10; $write_energy + $read_energy" | bc)

    # Mise à jour des totaux cumulatifs
    total_write_energy_cumulative=$(echo "$total_write_energy_cumulative + $write_energy" | bc)
    total_read_energy_cumulative=$(echo "$total_read_energy_cumulative + $read_energy" | bc)
    total_write_bytes_cumulative=$(echo "$total_write_bytes_cumulative + $totalWriteBytes" | bc)
    total_read_bytes_cumulative=$(echo "$total_read_bytes_cumulative + $totalReadBytes" | bc)
    total_energy_cumulative=$(echo "$total_energy_cumulative + $total_energy" | bc)

    # Affichage de l'énergie consommée
    #echo "Total des écritures disque: $totalWriteBytes Bytes"
    #echo "Total des lectures disque: $totalReadBytes Bytes"
    #echo "Énergie consommée par les écritures disque: $write_energy J"
    #echo "Énergie consommée par les lectures disque: $read_energy J"
    #echo "Énergie totale consommée par les activités disque: $total_energy J"
}



# Fonction pour gérer les options de la ligne de commande
getInput() {
    while getopts "n:i:" opt; do
        case $opt in
            n) processName=$OPTARG ;;
            i) interval=$OPTARG ;;
            \?) echo "Usage: cmd [-n] process_name [-i] interval" ;;
        esac
    done
}



# Fonction principale pour orchestrer le script
main() {
    getInput "$@"
    sudo echo "Authentification réussie"
  
    check_process_running "processName"

    data_collect
       
    
    
    find . -type f -name '*disk_raw*' | xargs rm -f

   
}

# Appel de la fonction principale
main "$@"
