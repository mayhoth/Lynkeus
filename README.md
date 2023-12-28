Lynkeus
=======

Lykeus is a tool to find parallel passages in Classical Greek and
Roman Literature. In the future it should be usuable with any of the
more important corpora available; at the moment, it supports only
querying the legacy database published by the Thesaurus Linguae
Graecae via the included versions of Peter Heslins
[Diogenes](https://d.iogen.es/d) Perl modules[^1] (support for the PHI
Latin corpus should be coming soon).

[^1] See the [Github repository](https://github.com/pjheslin/diogenes).

Requirements
------------
This is an early alpha version of Lynkeus, so installing and running
Lynkeus is at the moment quite adventurous. Things should get better
as soon as multiple system configurations have been tested sucessfully
and a proper build system has been implemented. Lynkeus has been
developed on Arch Linux for x86_64 and Termux on Android (Perl version
5.38); I have briefly tested it on Ubuntu, with some strange errors
which deleted the main part of the search results – this has to be
inspected soon.

It is planned to port Lynkeus to MacOS and Windows in the near
future.

The requirements are, in theory, quite small:

* Tcl and Tk 
* Perl with the Tcl and Tkx modules
* Groff (full installation) for export to PDF

Installing
--------

For Arch Linux, the commands are the following:

	pacman -S tk
	pacman -S perl # should be already present
	cpan Tkx

Then clone the git repository. Lynkeus shippes with the GentiumPlus
font, which can be found in the fonts directory. Install the TTS fonts
somewhere your system can find them.

For the pdf export to work, your groff distribution must have the
gropdf output device, the mom macro package and the GentiumPlus fonts
installed. On Arch, there should be a full groff distribution
preinstalled; Debian based distros have to install the groff package.
To install the fonts, run the install.pl script in the /fonts/groff
directory.

The main executable, lynkeus.pl, resides in /bin. On some systems,
there can be a problem with the shebang style lyneus uses; if you
encounter these, just change

	#! perl

into 

	#! /usr/bin/perl

or

	#! /usr/env/perl

or call Lynkeus with

	perl lynkeus.pl

