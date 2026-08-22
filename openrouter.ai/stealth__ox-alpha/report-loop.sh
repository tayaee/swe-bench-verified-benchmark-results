#!/bin/sh
while :
do
	./eval.sh
	./report.sh | tee results.txt
	if [ -n "$(git status --porcelain -- results.txt)" ]; then
		git add results.txt && git commit -m "Update results.txt" && git push
	fi
	sleep 3600
done
