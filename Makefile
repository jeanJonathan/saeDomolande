all: floc

floc: floc.sh
	@chmod +x floc.sh
	@cp floc.sh floc

clean:
	@rm -f floc
