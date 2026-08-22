#!/bin/sh
while :
do
	./eval.sh
	./report.sh | tee report.results.txt
	if [ -n "$(git status --porcelain -- results.txt)" ]; then
		git add report.results.txt && git commit -m "Update report.results.txt" && git push
	fi
	sleep 3600
done
