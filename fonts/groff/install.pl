#! /usr/bin/perl
# This script tries to implement the instructions given by Peter Schaffter
# at https://www.schaffter.ca/mom/momdoc/appendices.html#step-4

use v5.14;
use strict; use warnings;

use FindBin qw($Bin);
use File::Spec;
use File::Copy;

# Check if user is root
# die "This script needs root privileges to install the fonts\n" unless $<;

my $devps  = File::Spec->catdir("$Bin", "site-font", "devps");
my $devpdf = File::Spec->catdir("$Bin", "site-font", "devpdf");

my $groffdir = 0;
while ($groffdir eq 0) {
  say "Where is the groff installation located (default: /usr/share/groff)?";
  chomp ($groffdir = <STDIN>);
  $groffdir = $groffdir || File::Spec->catdir('/', 'usr', 'share', 'groff');
  unless (-d $groffdir) {
    say "$groffdir does not exist!";
    $groffdir = 0
  }
}
die "No write permissions for directory $groffdir" unless -w $groffdir;

my $site_font    = File::Spec->catdir("$groffdir", 'site-font');
my $groff_devps  = File::Spec->catdir("$site_font", 'devps');
my $groff_devpdf = File::Spec->catdir("$site_font", 'devpdf');
my $version      = "current";
my $groff_download_file = File::Spec->catfile
  ("$groffdir", "$version", 'font', 'devps', 'download');

my $download_devps  = File::Spec->catfile("$groff_devps", 'download');
my $download_devpdf = File::Spec->catfile("$groff_devpdf", 'download');

# Test if groff exists
die "Groff is not installed!" unless qx(groff -v);

# Test if gropdf module exists
my $err = qx(echo 'Hello World' | groff -mmom -Kutf8 -Tpdf -t 2>&1 1> /dev/null);
die "groff does not support the mom macro package or the gropdf device: Have you installed the full groff installation?" if $err;

# Make directories
for ($site_font, $groff_devps, $groff_devpdf) {
  mkdir $_, 0755 unless -d;
}

# Copy font files
chdir $devps;
for (glob "GentiumPlus*") {
  next if -l;
  copy $_, $groff_devps or die "Copy failed: $!";
}

chdir $devpdf;
for (glob "GentiumPlus*") {
  next if -l;
  copy $_, $groff_devpdf or die "Copy failed: $!";
}

# Make symbolic links to the groff font files in $groff_devpdf
chdir $groff_devps;
my @groff_fonts;
for (glob "GentiumPlus*") {
  next if /\.t42/;
  push @groff_fonts, $_;
}
chdir $groff_devpdf;
symlink File::Spec->catfile('..', 'devps', $_), $_ for @groff_fonts;

# modify download files – devps
chdir $devps;
if (-e $download_devps) {
  copy $download_devps, "$download_devps.bak";
}
else {
  copy $groff_download_file, $download_devps;
}

my $download_devps_data = <<EOT;
GentiumPlus\tGentiumPlus.t42
GentiumPlus-Italic\tGentiumPlus-Italic.t42
GentiumPlus-Bold\tGentiumPlus-Bold.t42
GentiumPlus-BoldItalic\tGentiumPlus-BoldItalic.t42
EOT

open APP, '>>', $download_devps
  or die "Cannot open groff's download file: $!";
print APP $download_devps_data;
close APP;

if (-e $groff_devpdf) {
  copy $download_devpdf, "$download_devpdf.bak";
}

# modify download files – devpdf
my $download_devpdf_data = <<EOT;
\tGentiumPlus\tGentiumPlus.pfa
\tGentiumPlus-Italic\tGentiumPlus-Italic.pfa
\tGentiumPlus-Bold\tGentiumPlus-Bold.pfa
\tGentiumPlus-BoldItalic\tGentiumPlus-BoldItalic.pfa
EOT

open APP, '>>', $download_devpdf
  or die "Cannot open groff's download file: $!";
print APP $download_devpdf_data;
close APP;
