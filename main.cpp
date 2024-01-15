#include <iostream>
#include <cstdlib>
#include <string>

int main() {
    int choice;
    std::cout << "Choose the shell script to execute: \n\n";
    std::cout << "1. Network Interface Card (NIC)\n";
    std::cout << "2. RAM\n";
    std::cout << "3. CPU\n";
    std::cout << "4. Hard Disk\n\n";

    std::cin >> choice;

    std::string shellCommand;

    switch (choice) {
        case 1:
            shellCommand = "sudo ./ePerfNIC.sh";
            break;
        case 2:
            shellCommand = "./ePerfRAM.sh";
            break;
        case 3:
            shellCommand = "./ePerfCPU.sh";
            break;
        case 4:
            shellCommand = "./ePerfDisk.sh";
            break;

        default:
            std::cout << "Invalid choice.\n";
            return 1;
    }

    int time;
    if(choice == 4) {
        std::string disk;
        std::cout << "Enter the disk device name: ";
        std::cin >> disk;
        std::cout << "Enter the time (in s): ";
        std::cin >> time;
        shellCommand += " -d " + disk + " -t " + std::to_string(time);
    } else {
        int process;
        std::cout << "Enter the PID of the process: ";
        std::cin >> process;
        std::cout << "Enter the time (in ms): ";
        std::cin >> time;
        shellCommand += " -p " + std::to_string(process) + " -t " + std::to_string(time);
    }

    int result = std::system(shellCommand.c_str());

    std::cout << result;
    if (result != 0) {
        std::cout << "Error during command execution.\n";
    }

    return 0;
}
