#!/bin/sh
while :
do
	./eval.sh
	(
		echo Last updated: $(date --iso-8601=sec)
		./report.sh
	) | tee report.results.txt
	if [ -n "$(git status --porcelain -- report.results.txt)" ]; then
		git add report.results.txt && git commit -m "Update report.results.txt" && git push
	fi
	sleep 1800
done
