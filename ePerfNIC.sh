#!/bin/bash


# Configuration de trap pour appeler force_stop lors de la réception de SIGINT
trap force_stop SIGINT
stop=false

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

    pid_array=($pids)
    pid_initial=($pids)
    pid_liste=($pid_pere)
    pid=$pid_liste

        #echo "Traitement en cours..."

        # Vérifie si le processus est toujours en cours d'exécution
        if ! is_process_running $pid; then
            #echo "Le processus avec le PID $pid n'est plus en cours d'exécution."
            continue
        fi

        if ! $stop; then
                continue
        fi

        # Capture du temps de début
        start_time=$(date +%s)

        # Nom des fichiers pour les données brutes et filtrées
        rawOutputFile="nethogs_raw_$pid.txt"
        filteredOutputFile="nethogs_filtered_$pid.txt"

        # Suppression des fichiers s'ils existent, pour s'assurer qu'ils sont recréés
        rm -f $rawOutputFile $filteredOutputFile

        # Exécution de nethogs pour le PID actuel en arrière-plan
        sudo nethogs -a -t -d $interval> $rawOutputFile &
        nethogs_pid=$!
        echo "Le programme est en cours d'execution..."

        # Boucle de surveillance pour arrêter nethogs si le processus n'est plus en cours d'exécution
        while is_process_running $pid; do
            sleep 1
        done

        # Arrêt de nethogs lorsque le processus surveillé se termine
        kill $nethogs_pid

        # Capture du temps de fin et calcul de la durée
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        #echo "Le processus $pid a tourné pendant $duration secondes depuis le début du tracking."

       for pidCalcul in "${pid_initial[@]}"; do
                grep "$pidCalcul" $rawOutputFile >> $filteredOutputFile
            done

        calculateNICEnergy
    
}




# Fonction pour calculer l'énergie consommée par les activités disque
calculateNICEnergy() {

    if [ ! -f ./nicParam.conf ]; then
    echo "Le fichier de configuration n'a pas été trouvé."
    exit 1
    fi
    source ./nicParam.conf
    # Initialisation des variables pour les lectures et écritures disque
    # Initialisation des variables pour le trafic envoyé et reçu
totalSent=0
totalReceived=0

max_download_power=0.55
max_upload_power=1.029
max_download_rate=150500
max_upload_rate=152500


    # Nom du fichier contenant les données filtrées
filteredOutputFile="nethogs_filtered_$pid.txt"

    # Lecture du fichier ligne par ligne
while IFS= read -r line; do
    # Extraction des valeurs de trafic envoyé et reçu à partir de la ligne
    # Supposons que le format soit 'PID User Program Sent Received'
    # Ajustez les positions (awk '{print $X}') selon votre format de sortie spécifique
    sent=$(echo $line | awk '{print $(NF-1)}')
    received=$(echo $line | awk '{print $NF}')
    count=$(echo "$count + 1" | bc  2>/dev/null) 

     # Conversion des valeurs en nombres et ajout aux totaux
    totalSent=$(echo "$totalSent + $sent" | bc 2>/dev/null)
    totalReceived=$(echo "$totalReceived + $received" | bc  2>/dev/null)

done < "$filteredOutputFile"

   #from internet
   

    upload_power=$(echo "scale=10;$max_upload_power*($totalSent / $max_upload_rate)" | bc  2>/dev/null)
    download_power=$(echo "scale=10;$max_download_power*($totalReceived / $max_download_rate)"| bc  2>/dev/null)

    nic_power_AVG=$(echo  "scale=10;$upload_power + $download_power" | bc  2>/dev/null)
    nic_energy=$(echo "scale=10;$nic_power_AVG*$duration*0.001" | bc  2>/dev/null)

    echo "Total des données envoyées: $totalSent KB"
    echo "Total des données reçus: $totalReceived KB"
    echo "Consommation energétique de la carte réseau en J": $nic_energy
    echo "Consommation energétique de la carte réseau en W": $nic_power_AVG

    

   


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
       
    
    
    find . -type f -name '*nethogs_raw*' | xargs rm -f
    find . -type f -name '*nethogs_filtered*' | xargs rm -f


}

# Appel de la fonction principale
main "$@"
