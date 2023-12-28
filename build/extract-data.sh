#! /bin/sh
LynkeusDir=$(dirname $0)/..

tar -xzvf $LynkeusDir/data/greek-analyses.tar.gz
mv greek-analyses/greek-analyses.txt $LynkeusDir/data/
mv greek-analyses/greek-lemmata.txt $LynkeusDir/data/
rmdir greek-analyses
