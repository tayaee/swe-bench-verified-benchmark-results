#!/bin/bash

RESULTS_FILE=report.results.$(cat /etc/machine-id | cut -b1-8).txt
while :
do
	./eval.sh
	./report.sh | tee $RESULTS_FILE
	git pull
	if [ -n "$(git status --porcelain -- $RESULTS_FILE)" ]; then
		git add $RESULTS_FILE && git commit -m "Update $RESULTS_FILE" && git push
	fi
	read -t 600 -p "Wait 600s or press ENTER to continue..." < /dev/tty
done
