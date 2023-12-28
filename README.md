Lynkeus
=======

Lynkeus is a tool to find parallel passages in Classical Greek and
Roman Literature. In the future it should be usable with any of the
more important corpora available; at the moment, it supports only
querying the legacy database published by the Thesaurus Linguae
Graecae via the included versions of Peter Heslins
[Diogenes](https://d.iogen.es/d) Perl modules[^1] (support for the PHI
Latin corpus should be coming soon).

[^1] See the [Github repository](https://github.com/pjheslin/diogenes).

Requirements
------------
This is an early alpha version of Lynkeus, so installing and running
Lynkeus has to be done by hand. Things should get better as soon as
multiple system configurations have been tested successfully and a
proper build system has been implemented. 

It is planned to port Lynkeus to MacOS and Windows in the near
future.

The requirements are, in theory, only a few:

* Tcl and Tk 
* Perl with the Tcl and Tkx modules (to install these, you need make and  a C compiler)
* Groff (full installation) for export to PDF

The intended version of Perl is 5.14+, but due to some bug in the
modified Diogenes libraries, Perl 5.36+ is required (variable length
lookbehind support). I will tackle this problem shortly. Lynkeus has been
developed on Arch Linux (x86_64) and Termux on Android, where it runs
fine. It also works as intended on Ubuntu 23.10 (Perl 5.36), but it
does not so on Ubuntu 22.04 LTS or Linux Mint, probably due to Perl
5.34.

Installing
----------
For Arch Linux, the commands are the following:

	pacman -S base-devel
	pacman -S tk
	pacman -S perl # should be already present
	cpan Tcl Tkx
	
For Ubuntu, do the following:

	sudo apt install build-essential # for make and gcc
	sudo apt install perl            # should be already present
	sudo cpan Tcl Tkx

Then clone the git repository. Lynkeus ships with the GentiumPlus
font, which can be found in the fonts directory. Install the TTS fonts
somewhere your system can find them.

Because of the 100MB limit of GitHub, the essential analyses files
needed for the lemma search mode have been compressed and must be
uncompressed. The archive is /data/greek-analyses.tar.gz, both files must go into the /data folder. You can use the shell script included in /build

	/PATH/TO/Lynkeus/build/extract-data.sh

For the pdf export to work, your groff distribution must have the
gropdf output device, the mom macro package and the GentiumPlus fonts
installed. On Arch, there should be a full groff distribution
preinstalled; Debian based Linux distributions include only a minimal
groff environment by default, so the full groff package has to be
installed manually:

	sudo apt install groff

To install the fonts, run the install.pl script in the /fonts/groff
directory.

	cd /PATH/TO/Lynkeus
	sudo perl fonts/groff/install.pl

The main executable, lynkeus.pl, resides in /bin. You can execute it with

	cd /PATH/TO/Lynkeus
	bin/lynkeus.pl      # or perl bin/lynkeus.pl
	
For your convenience, you can rite a simple wrapper script, make it
executable and move it somewhere in your $PATH:

	echo '#! /bin/sh
	exec perl /PATH/TO/Lynkeus/bin/lynkeus.pl "$@"' > lynkeus
	chmod 755 lynkeus
	mv lynkeus /SOMEWHERE/IN/YOUR/PATH

Note on save files
------------------
One valid lynkeus save file (*.lyn) can be given as an argument;
Lynkeus will load it automatically. But beware: these save files are
architecture specific and cannot be ported from one architecture to
another. What is more, future changes in Lynkeus can easily affect the
load behaviour. Using old save files on newer versions can lead to a
segmentation fault.

