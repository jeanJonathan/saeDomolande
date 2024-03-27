#!/bin/bash

# ================================================================
# Auteurs : Jean-Jonathan Koffi, Noah Gomes
# Date de création : 21/03/2024
#
# Description :
# Ce script agit comme un contrôleur pour la mesure de la consommation d'énergie des composants système.
# Il permet d'orchestrer l'exécution des scripts de performance pour le CPU (ePerfCPU.sh), la RAM (ePerfRAM.sh),
# le disque (ePerfDISK.sh) et la carte réseau (ePerfNIC.sh), soit individuellement soit tous ensemble.
# L'utilisateur peut spécifier le composant à mesurer, le nom du processus et l'intervalle de temps entre les mesures.
# Exemple d'utilisation :
# ./floc.sh -a ALL -n firefox -i 10
# Exécute tous les scripts de performance pour le processus 'firefox' avec un intervalle de 10 secondes.
#
# Remarques :
# Les scripts enfants sont lancés en arrière-plan et le script principal doit être exécuté avec des privilèges suffisants
# pour permettre la lecture des données système nécessaires. Assurez-vous que tous les scripts de mesure associés
# sont présents dans le même répertoire que floc.sh et qu'ils ont les permissions d'exécution appropriées.
# ================================================================


getInput() {
    # Traitement des arguments de la ligne de commande
    while getopts "a:n:i:" opt; do
        case ${opt} in
            a) app=$OPTARG ;;
            n ) processName=$OPTARG ;;
            i ) interval=$OPTARG ;;
            \? ) echo "Usage: cmd -a [APP] -n [NOM DU PROCESSUS] -i [INTERVAL]" ;;
        esac
    done

    case $app in
        "NIC")
            echo "Exécution de ePerfNIC pour le processus '$processName' avec un intervalle de $interval secondes."
            ./ePerfNIC.sh -n "$processName" -i "$interval"
            ;;
        "DISK")
            echo "Exécution de ePerfDISK pour le processus '$processName' avec un intervalle de $interval secondes."
            ./ePerfDISK.sh -n "$processName" -i "$interval"
            ;;
        "RAM")
            echo "Exécution de ePerfRAM pour le processus '$processName' avec un intervalle de $interval secondes."
            ./ePerfRAM.sh -p "$processName" -t "$interval"
            ;;
        "CPU")
            echo "Exécution de ePerfCPU pour le processus '$processName' avec un intervalle de $interval secondes."
            ./ePerfCPU.sh -p "$processName" -t "$interval"
            ;;
        "ALL")
            echo "Exécution de tous les scripts de performance pour le processus '$processName'."
            ./ePerfCPU.sh -p "$processName" -t "$interval" &
            ./ePerfRAM.sh -p "$processName" -t "$interval" &
            ./ePerfDISK.sh -n "$processName" -i "$interval" &
            ./ePerfNIC.sh -n "$processName" -i "$interval" &
            ;;
        *)
            echo "Option invalide : doit être NIC, DISK, CPU, RAM ou ALL"
            exit 1
            ;;
    esac
}

main() {
    getInput "$@"
}

# Appel de la fonction principale
main "$@"




main() {
    getInput "$@"
}

# Appel de la fonction principale
main "$@"