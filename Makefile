# Makefile which compilates and executes the program.
# type "make clean" to clean up generated files
# type "make run" to compilates et executes program 


# Compiler and its flags
CXX = g++
CXXFLAGS = -std=c++11 -Wall

# List every file we need to check permissions of
FILES = ePerfCPU.sh ePerfDisk.sh ePerfNIC.sh 
# ePerfNIC.sh ePerfRAM.sh

# Rule to build all targets: check_permissions and main
all: check_permissions main

# Rule to compile the program
main: main.cpp
	$(CXX) $(CXXFLAGS) -o main main.cpp

# Rule to run the compiled program
run: main
	./main

# Check permissions for 4 files
check_permissions: $(FILES)
	@echo "Checking permissions..."
	@for file in $^; do \
		if [ ! -e $$file ]; then \
			echo "File $$file does not exist."; \
		elif [ ! -x $$file ]; then \
			chmod +x $$file; \
			echo "Permissions for $$file have been set."; \
		else \
			echo "Permissions for $$file are already set."; \
		fi \
	done

# Rule to clean up generated files
clean:
	rm -f main
