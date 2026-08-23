#!/bin/bash

RESULT_FILE=benchmark.result.$(cat /etc/machine-id | cut -b1-8).txt
while :
do
	./eval.sh
	./report.sh | tee $RESULT_FILE
	git pull
	if [ -n "$(git status --porcelain -- $RESULT_FILE)" ]; then
		git add $RESULT_FILE && git commit -m "Update $RESULT_FILE" && git push
	fi
	read -t 600 -p "Wait 600s or press ENTER to continue..." < /dev/tty
done
