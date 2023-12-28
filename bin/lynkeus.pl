#! /usr/bin/perl
use v5.14;
use strict;
use warnings;

# use Memory::Usage;
# our $mu = Memory::Usage->new();
# $mu->record('starting work');

use Tkx;
use utf8;
use Storable qw(store retrieve freeze thaw);

# for diacritis insensitive comparisons and matches
use Unicode::Collate;
our $Collator = Unicode::Collate->new
  (normalization => undef, level => 1);
use Data::Dumper;
use Encode;
use POSIX qw(WNOHANG);

use Cwd qw(abs_path);
use FindBin qw($Bin);
use File::Spec;
use File::Temp qw(tempfile tempdir);
use lib File::Spec->catdir($Bin, '..', 'lib');
use Diogenes::Search;
use Diogenes::Indexed;
use Diogenes::Browser;

binmode STDOUT, ':utf8';
# use open qw( :std :encoding(UTF-8) );

our $VERSION = '0.1.0';

#----------------------------------------------------------------------
# LOAD CONFIG FILE
#----------------------------------------------------------------------

# Search Types
our $select_st_lemma;
our $select_st_synonyma;
our $select_st_continentia;
our $select_si_corpus;

# Language
our $gui_lang = 'en';
if ($ENV{LANG} and $ENV{LANG} =~ /^[^_]+/ ) {
  say my $lang = $&;
  my %languages = find_languages();
  for my $key (keys %languages) {
    $gui_lang = $lang and last if $lang eq $key;
  }
}

our $default_threshold_percent;

# Browser apperance
our $browser_column_count;
our ($config_dir, $config_file);
read_config_file();

sub find_config_dir {
  if ( $ENV{XDG_CONFIG_HOME} ) {
    return File::Spec->catdir ($ENV{XDG_CONFIG_HOME}, 'Lynkeus');

  }
  elsif ( $ENV{HOME} ) {
    return File::Spec->catdir ($ENV{HOME}, '.config', 'Lynkeus');
  }
  else {
    die "Could not find path to configuration file:
Please set the \$HOME environment variable!";
  }
}

sub make_config_dir {
  unless ( -d $config_dir ) {
      if ( not $ENV{XDG_CONFIG_HOME}
	   and not -d File::Spec->catdir($ENV{HOME}, '.config') ) {
	mkdir File::Spec->catdir($ENV{HOME}, '.config');
      }
      mkdir $config_dir;
    }
}

sub read_config_file {
  my ($attrib, $val);
  my %config = (
		search_type => 'verbatim',
		corpus => 'TLG',
		language => $gui_lang,
		threshold => '30',
		browser_columns => '3',
		tlg_dir => '',
		phi_dir => '',
		ddp_dir => '',
	       );

  $config_dir  = find_config_dir();
  $config_file = File::Spec->catfile($config_dir, 'lynkeus.conf');

  if (-e $config_file ) {
    say "Found configuration file";
    # get configuration data
    open my $fh, '<:utf8', $config_file
      or die  "Could not open configuration file: $!";
    while (<$fh>) {
      next if m/^#/;
      next if m/^\s*$/;
      ($attrib, $val) = m#^\s*(\w+)[\s=]+((?:"[^"]*"|[\S]+)+)#;
      $val =~ s#"([^"]*)"#$1#g;
      die "Error parsing $config_file for $attrib and $val: $_\n"
	unless $attrib and defined $val;
      $attrib =~ s/-?(\w+)/\L$1/;
      $attrib =~ tr/A-Z/a-z/;
      die "Configuration file error in parameter: $attrib\n"
	unless exists $config{$attrib};
      $config{$attrib} = $val;
    }
    close $fh;

    # validate the data
    warn <<EOT
Error in configuration file $config_file:
Search_type must be 'verbatim' or 'lemma[+synonyma][+continentia}!
Setting search_type to verbatim..."
EOT
      unless $config{search_type} =~ /verbatim/
      or $config{search_type} =~ /lemma/;

    # Check if the paths to the corpora have been specified,
    # validate the paths and load them into environment variables
    warn "No path to TLG data specified in $config_file"
      unless $config{tlg_dir};
    # die "No path to PHI data specified in $config_file"
    # 	unless $config{phi_dir};
    # die "No path to DDP data specified in $config_file"
    # 	unless $config{ddp_dir};
    warn "Invalid path to TLG corpus: Could not find authtab.dir!"
      unless -e File::Spec->catfile($config{tlg_dir}, 'authtab.dir');
    $ENV{TLG_DIR} = $config{tlg_dir} if $config{tlg_dir};
    $ENV{PHI_DIR} = $config{tlg_dir} if $config{phi_dir};
    $ENV{DDP_DIR} = $config{tlg_dir} if $config{ddp_dir};
  }
  else {
    my $diogenes_config_dir = Diogenes::Base->get_user_config_dir();
    my @diogenes_files = ( File::Spec->catfile($diogenes_config_dir, 'diogenes.prefs'),
			   File::Spec->catfile($diogenes_config_dir, 'diogenes.config') );
    my (%diogenes_config, $attrib, $val);
    for my $rc_file (@diogenes_files) {
      next unless -e $rc_file;
      open RC, '<:encoding(UTF-8)', "$rc_file" or die ("Can't open (apparently extant) file $rc_file: $!");
      while (<RC>) {
	next if /^#/ or /^\s*$/;
	($attrib, $val) = m#^\s*(\w+)[\s=]+((?:"[^"]*"|[\S]+)+)#;
	$val =~ s#"([^"]*)"#$1#g;
	die "Error parsing $rc_file for $attrib and $val: $_\n" unless 
	  $attrib and defined $val;
	$diogenes_config{$attrib} = $val;
      }
    }
    if ( $diogenes_config{tlg_dir} ) {
      warn "Could not find configuration file:
Using Diogenes' TLG path instead!\n";
      $ENV{TLG_DIR} = $diogenes_config{tlg_dir};
    }
    else {
      warn "No configuration file found\n";

      if ( $ENV{TLG_DIR}
	   and -e File::Spec->catfile($ENV{TLG_DIR}, 'authtab.dir') ) {
	$ENV{TLG_DIR} = abs_path $ENV{TLG_DIR}; # just in case
	warn "Using path of the TLG_DIR environment variable!\n";
      }
      else {
	our %languages = find_languages();
	edit_configuration('startup');
	exit;
      }
    }
  }

  # load data info the defined global configuration variables
  $select_st_lemma       = ($config{search_type} =~ /lemma/)       ? 1 : 0;
  $select_st_synonyma    = ($config{search_type} =~ /synonyma/)    ? 1 : 0;
  $select_st_continentia = ($config{search_type} =~ /continentia/) ? 1 : 0;
  $select_si_corpus          = $config{corpus};
  $gui_lang                  = $config{language};
  $default_threshold_percent = $config{threshold};
  $browser_column_count      = $config{browser_columns};
  $browser_column_count--;
}

#----------------------------------------------------------------------
# STARTUP OF THE WORKER PROCESSES
#----------------------------------------------------------------------

our $CORES      = get_nr_of_cores();
our $PARENT_PID = $$;
our (@pid, @from_parent, @from_child, @to_parent, @to_child);
our $path = tempdir( CLEANUP => 1 );

create_worker_processes();

#----------------------------------------------------------------------

sub get_nr_of_cores {
  # Portable solution: Sys::Info::Device::CPU?
  open my $handle, "/proc/cpuinfo"
    or die "Can't open cpuinfo: $!\n";
  (my $CORES = map /^processor/, <$handle>)--;
  close $handle;
  return $CORES;
}

sub create_worker_processes {
  for my $i (0..$CORES) {
    # Make the pipes
    pipe($from_parent[$i], $to_child[$i])
      or die "Cannot open child pipes!";
    pipe($from_child[$i],  $to_parent[$i])
      or die "Cannot open parent pipes!";
    $to_child[$i]->autoflush(1);
    $to_parent[$i]->autoflush(1);
    $from_child[$i]->blocking(0);

    # Fork
    $pid[$i] = fork()
      // die "cannot fork to core $i: $!";

    # Child
    if (not $pid[$i]) {
      # Close parent's pipes to the child
      close $from_child[$i] && close $to_child[$i]
	or die "PID $$ cannot close parent's pipes: $!";

      # Child's global variables
      our $num = $i;

      # Signal handlers
      # local $SIG{HUP} = \&shutdown_child;
      # local $SIG{INT} = \&shutdown_child;
      local $SIG{USR1} = sub { die "$num ($$): Aborting...!" };
      # local $SIG{USR2} = sub { say "$num ($$): Stopping...!"};

      my $iteration = 1;
      while (kill 0, $PARENT_PID) { # check if parent is still running
	say "Child $num (PID $$), beginning iteration $iteration";
	eval { child_main($num) };
	say "$@";
	$iteration++;
	$to_parent[$num]->print("EOF\n");
      }

      close $from_parent[$num] && close $to_parent[$num];
      die "$num: Exiting...\n";
    }

    # Parent
    close $from_parent[$i] &&  close $to_parent[$i]
      or die "Parent (PID $$) cannot close pipes of child no $i: $!";
  }
}

sub child_main {
  my $num = shift;

  # CHILD'S MAIN LOOP
  my $line = '';
  while(1) {
    my $word = $from_parent[$num]->getline();
    chomp $word;
    my @patterns;
    while ( $line = $from_parent[$num]->getline() ) {
      next unless defined $line;
      last if $line eq "\n";
      chomp $line;
      push @patterns, $line;
    }
    my @author_nums;
    while ( $line = $from_parent[$num]->getline() ) {
      next unless defined $line;
      last if $line eq "\n";
      chomp $line;
      push @author_nums, $line;
    }

    say "HERE is child nr. $num (PID $$), I've got the following to do:";
    say "Search for $word";
    for my $i (0..$#patterns) {
      say "Pattern $i: $patterns[$i]";
    }
    my $filename = corpus_search
      ($word, \@patterns, \@author_nums, $to_parent[$num]);
    if ( $filename ) {
      print("[CORE $num, PID $$]\t Wrote $filename!\n");
      $to_parent[$num]->say($filename);
    }
    else {
      say STDERR "ERR $num: $!";
      $to_parent[$num]->say("ERROR: $!");
    }
  }
}

sub corpus_search {
  my $word = shift;
  my $patterns = shift;
  my $author_nums = shift;
  my $parent_fh = shift;

  my $type = shift @$author_nums;

  # do the search, redirect STDOUT TO $out_string
  my $query = Diogenes::Search->new
    (
       -type => $type,
       -pattern_list => $patterns,
    );
  $query->{lynkeus_fh} = $parent_fh;

  my $result;
  {
    local *STDOUT;
    open STDOUT, '>:raw', \$result;
    my $count = 0;
    say { $parent_fh} "A: $count 0";
    for my $author_num (@$author_nums) {
      $query->select_authors(-author_nums => [ $author_num ]);
      $query->pgrep;
      say { $parent_fh} "A: ", ++$count,  " $author_num";
    }
  }
  $result = '' unless defined $result;

  my $data = {};
  $data->{result}          = \$result;
  $data->{hits}            = $query->get_hits();
  $data->{seen_all}        = $query->{seen_all};
  $data->{match_start_all} = $query->{match_start_all};
  $data->{not_printed}     = $query->{not_printed};

  my $filename = File::Spec->catfile("$path", "$word.dat");
  eval {store $data, $filename};
  return ($@)
    ? undef
    : $filename;
}

sub kill_worker_processes {
  # for my $i (0..$CORES) {
  #   close $from_child[$i] && close $to_child[$i]
  #     or die "Cannot close pipes to child $i (PID pid[$i]): $!";
  #   say "Closed pipe to and from worker $i";
  # }
  for my $i (0..$CORES) {
    kill HUP => $pid[$i];
    waitpid($pid[$i], 0);
    say "Killed off worker no. $i!";
  }
}

#----------------------------------------------------------------------
#----------------------------------------------------------------------
# SYSTEM-SPECIFIC VARIABLES
our $windowing_system = Tkx::tk_windowingsystem();

# Test is groff works and has GentiumPlus installed
our $groff_available = `groff -v`;
if ($groff_available) {
  my $err = qx(echo '.FAMILY GentiumPlus' | groff -mmom -Kutf8 -Tpdf -t 2>&1 1> /dev/null);
  if ($err) {
    say "Groff error:\n${err}Groff export disabled" if $err;
    $groff_available = undef;
  }
}

our $autoscroll = 1;

# Scaling on Windows is off
# Autoscaling does not work either (tklib is not installed)
if ($^O =~ /win/i) {
  $autoscroll = 0;
  Tkx::tk('scaling', '3')
}

# activate autoscroll if tklib is installed
if ( $autoscroll ){
  my $autoscroll_path =
    File::Spec->catdir($Bin, '..', 'lib', 'autoscroll');
  Tkx::eval("lappend auto_path \"$autoscroll_path\"");
  # Tkx::eval("package require autoscroll");
  Tkx::package_require("autoscroll");
  $autoscroll = 1;
}
# Tkx::i::call("::autoscroll::wrap); # Funktioniert nicht!

#----------------------------------------------------------------------
# TK THEMES

# say Tkx::ttk__style_theme_names();
Tkx::ttk__style_theme_use('clam') if $windowing_system eq 'x11';

# if ($windowing_system eq 'x11') {
#   my $ttk_breeze_path =
#     File::Spec->catdir($Bin, '..', 'lib', 'ttk-Breeze');
#   Tkx::eval("lappend auto_path \"$ttk_breeze_path\"");
#   Tkx::package_require("ttk::theme::Breeze");
#   # Tkx::eval("package require ttk::theme::Breeze");
#   Tkx::ttk__style_theme_use('Breeze');
# }

#----------------------------------------------------------------------
# FONTS
our $normal_size = 11;
our $small_size  = ($normal_size - 2);
our $big_size    = ($normal_size + 2);
our $gentium_available;
our $gentium;
{
  my $font_families = Tkx::font_families();
  if ($font_families =~ /(^|\s)Gentium($|\s)/) {
    $gentium_available = 1;
    $gentium = 'Gentium';
  }
  if ($font_families =~ /(^|\s)GentiumPlus($|\s)/) {
    $gentium_available = 1;
    $gentium = 'GentiumPlus';
  }
}

if ($gentium_available) {
  Tkx::font_configure('TkDefaultFont',      -family => $gentium, -size => $normal_size);
  Tkx::font_configure('TkTextFont',         -family => $gentium, -size => $normal_size);
#  Tkx::font_configure('TkFixedFont',        -family => $gentium, -size => $normal_size);
  Tkx::font_configure('TkMenuFont',         -family => $gentium, -size => $normal_size);
  Tkx::font_configure('TkHeadingFont',      -family => $gentium, -size => $normal_size);
  Tkx::font_configure('TkIconFont',         -family => $gentium, -size => $normal_size);
  Tkx::font_configure('TkCaptionFont',      -family => $gentium, -size => $big_size);
  Tkx::font_configure('TkSmallCaptionFont', -family => $gentium, -size => $small_size);
  Tkx::font_configure('TkTooltipFont',      -family => $gentium, -size => $small_size);
}

#----------------------------------------------------------------------
# PERSEUS FILES

# greek-analyses.txt
our %greek_analyses_indices;
our $greek_analyses_file =
  File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.txt');
our $greek_analyses_index =
  File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.idx');

sub load_greek_analyses_index {
  if (-e $greek_analyses_index) {
    read_greek_analyses_index();
  }
  else {
    make_greek_analyses_index();
    write_greek_analyses_index();
  }
}

sub make_greek_analyses_index {
  open my $analyses_fh, '<:raw', $greek_analyses_file
      or die "Unable to load analyses file: $!\n";
  $greek_analyses_indices{EOF} = -s $greek_analyses_file;

  my @alphabet = split //, 'abcdefghiklmnopqrstuwxyz';
  my $letter = shift @alphabet;
  while (<$analyses_fh>) {
    if (m/^$letter/) {
      $greek_analyses_indices{$letter} =
	tell($analyses_fh) - length($_);
      $letter = shift @alphabet
	or last;
    }
  }
}

sub write_greek_analyses_index {
  open FH, '>', $greek_analyses_index
    or die "Unable to open analyses index: $!\n";
  say FH "$_ $greek_analyses_indices{$_}"
    for sort
    { $greek_analyses_indices{$a} <=> $greek_analyses_indices{$b} }
    keys %greek_analyses_indices;
  close FH;
}

sub read_greek_analyses_index {
  open FH, '<', $greek_analyses_index
    or die "Unable to load analyses index: $!\n";
  while (<FH>) {
    if (m/([a-ik-uw-z]|EOF) (\d+)/) {
      $greek_analyses_indices{$1} = $2;
    }
  }

  my @alphabet = split //, 'abcdefghiklmnopqrstuwxyz';
  for (@alphabet) {
    die "Error in $greek_analyses_index"
      unless exists $greek_analyses_indices{$_};
  }
}

#----------------------------------------------------------------------
# LOCALISATION
our %ls;				# ls stand for locale string
our %languages = find_languages();

# Function that gets the available languages
sub find_languages {
  my %lang;
  eval {
    my $locale_dir = File::Spec->catdir($Bin, '..', 'data', 'locale');
    opendir my $dh, $locale_dir
      or die
      "I was not able to open directory $locale_dir,
which should hold the language files: Falling back to English!\n";
    my @files = readdir $dh;

    for my $file (@files) {
      next unless $file;
      next unless $file =~ /^[_a-z]+$/;	# only lc ASCII characters or underscores
      open my $fh, '<:utf8', File::Spec->catfile($locale_dir, $file)
	or warn "Cannot open locale file $file: $!\n";
      chomp (my $langname = <$fh>);
      $lang{$file} = $langname if $langname;
      close $fh;
    }
    closedir $dh;
  };
  $lang{en} = 'English';
  return %lang;
}

# Function that sets the locale strings according to the language
sub gui_lang{
  $ls{search} = 'Search';
  $ls{new}    = 'New';
  $ls{save}   = 'Save';
  $ls{load}   = 'Load';
  $ls{close}  = 'Close';
  $ls{quit}   = 'Quit';

  $ls{pref}   = 'Preferences';
  $ls{lang}   = 'Language';
  $ls{help}   = 'Help';
  $ls{manual} = 'Lynkeus Manual';
  $ls{about}  = 'About Lynkeus';

  $ls{passage} = 'Passage';
  $ls{export}    = 'Export';
  $ls{delete_selection} = 'Delete selection';
  $ls{undo}   = 'Undo';
  $ls{show_context} = 'Show context';
  $ls{export_to_txt} = 'Export as Plain Text File';
  $ls{export_to_mom} = 'Export as Groff Mom File';
  $ls{export_to_pdf} = 'Export as PDF Document';

  $ls{search_type} = 'Search type';
  $ls{verbatim}    = 'verbatim';
  $ls{lemma}       = 'lemma';

  $ls{synonyma}      = 'verba synonyma';
  $ls{continentia}   = 'verba continentia';
  $ls{search_in}     = 'Search in';
  $ls{define_corpus} = 'Define Corpus';

  $ls{input}          = 'Input';
  $ls{lemmata}        = 'Lemmata';
  $ls{single_results} = 'Hits for single words';
  $ls{result}         = 'Parallel passages';
  $ls{statistics}     = 'Statistics';
  $ls{cancel}         = 'Cancel';
  $ls{total}          = 'Total';
  $ls{apply}          = 'Apply';
  $ls{ok}             = 'Ok';

  $ls{form}           = 'Form';
  $ls{single_forms}   = 'Forms';
  $ls{pattern}        = 'pattern';
  $ls{pattern_ed}     = 'Pattern Editor';
  $ls{browser}        = 'Browser';
  $ls{for}            = 'for';

  $ls{select_all}     = 'Select all';
  $ls{select_none}    = 'Select none';

  $ls{search_term}  = 'Search term';
  $ls{numberofhits} = 'Hits';
  $ls{weight}       = 'Weight';
  $ls{edit}         = 'Edit';
  $ls{continue}     = 'Continue';

  $ls{view}     = 'View';
  $ls{add}      = 'Add';
  $ls{remove}   = 'Remove';
  $ls{increase} = 'Add';
  $ls{decrease} = 'Remove';
  $ls{change}   = 'Change';
  $ls{result}   = 'Result';

  $ls{context}  = 'Context';
  $ls{contexts} = 'Character Clause Sentence Line';
  $ls{Contexts} = 'Characters Clauses Sentences Lines';

  $ls{threshold}  = 'Threshold';

  $ls{list_st}      = 'Search terms';
  $ls{total_weight} = 'Total weight';

  $ls{preparing}  = 'Preparing';
  $ls{evaluating} = 'Evaluating';

  $ls{new_search}      = 'Neue Suche';
  $ls{message_discard} = 'Are you sure you want to discard the current search?';

  $ls{path_tlg} = "Path to TLG data";
  $ls{path_phi} = "Path to PHI data";
  $ls{path_ddp} = "Path to DDP data";
  $ls{browse}   = "Browse";
  $ls{defaults}    = "Default setrings";
  $ls{browsercols} = "Browser columns";

  $ls{error_empty}  = 'Please enter a text!';
  $ls{error_save}   = 'could not save';
  $ls{error_unknown_st} = 'Unknown corpus:';
  $ls{error_implemented_PHI} = 'PHI not yet implemented!';
  $ls{error_implemented} = 'Not yet implemented!';
  $ls{error_select}  = 'Please select a search term!';
  $ls{error_results}  = 'No results!';
  $ls{error_lemma}  = 'No results for';

  $ls{save_nothing} = 'There is nothing to save!';
  $ls{save_success} = 'Current serach saved sucessfully!';
  $ls{save_failure} = 'Could not save current search:';
  $ls{load_failure} = 'Could not load file:';
  $ls{load_wrong_format} = 'File has the wrong file format!';

  $ls{groff_success} = 'Groff finished successfully!';
  $ls{groff_failure} = 'Groff failed!';
  $ls{log} = 'Would you like to see the log file?';


  if    ($gui_lang eq 'en') {  }
  else {
    eval {
      open my $locale_fh, '<:utf8',
	File::Spec->catfile
	  ($Bin, '..', 'data', 'locale', "$gui_lang")
	  or die
	  "I was not able to load the language file $gui_lang: $!\n";

      while (<$locale_fh>) {
 	chomp;
	s/#.*//;
	s/^\s+//;
	s/\s+$//;
	next unless length;
	next unless /=/;

	my ($key, $value) = split(/\s*=\s*/, $_, 2);
	$ls{$key} = $value if exists $ls{$key};
      }
    };

    # Error handling
    if ($@) {
      say $@;
      $gui_lang = 'en';
      gui_lang()
    }
  }
}

gui_lang();

#----------------------------------------------------------------------
# BLACKLIST

our @blacklist = ();
eval { import_blacklist() };
error($@) if $@;

sub import_blacklist{
  open my $blacklist_fh, '<:utf8',
    File::Spec->catfile($Bin, '..', 'data', 'blacklist.txt')
    or die "Unable to load blacklist file: $!\n";

  @blacklist = ();
  while (<$blacklist_fh>) {
    next if m/^#/;		# Skip commented lines
    while (m/\S+/g) {
      my $w = $&;
      # original utf8 word
      push @blacklist, $w;

      # translate to beta code, strip diacritics
      $w = lc Diogenes::UnicodeInput->unicode_greek_to_beta($w);
      $w =~ tr#/\\|()=\*##d;
      push @blacklist, $w;
    }
  }

  close $blacklist_fh
}

#----------------------------------------------------------------------
# GLOBAL VARIABLES
#----------------------------------------------------------------------

# our $out_string;
our $searching = 0;
our $interrupt = 0;
our $printer_interrupt = 0;
our $input_str;
our @words = ();
our %results = ();
our %output = ();
our %textframes;
our %deleted_passages;		# Actual blacklist for passages to be ignored in the evaluation
our %elided_passages;		# Index of elided ('deleted') passages in the viewers
our %open_viewers;

our $st_lemma;
our $st_synonyma;
our $st_continentia;
our $si_corpus;

our @context_types = qw(character clause sentence line);
our @context_types_str_sing = split /\s+/, $ls{contexts};
our @context_types_str_plur = split /\s+/, $ls{Contexts};
die "Error in configuration file $gui_lang: contexts must include $#context_types items!"
  unless $#context_types == $#context_types_str_sing;
die "Error in configuration file $gui_lang: Contexts must include $#context_types items!"
  unless $#context_types == $#context_types_str_plur;

our $context = 100;
our @context_types_str = ($context > 1)
  ? @context_types_str_plur
  : @context_types_str_sing;
our $context_type = 'character';
our $context_type_str = get_context_type_str();

our $threshold;

our $progress_frm;
our $progress_t_frm;
our $progress_t_bar;
our $progress_t_l;

our $progress_w_cnt;

our @selected_str;
our @selected_num;
our $weight;

# Lemma search specific
our %lemmata;
our $g_stem_min = 1;
our $g_max_alt = 50;
our $g_chop_optional_groups = 0;

# Helper Diogenes Search object
our $tlg_lister = Diogenes::Search->new(-type => 'tlg', -pattern => ' ');

# Browser
our $tlg_browser = Diogenes::Browser::Lynkeus->new(-type => 'tlg');
our (@browser_buffers, @browser_headers, @browser_indices);

# mouse button state (viewer; needed for correct selecting when dragging)
our $textframe_mouse_pressed;
#----------------------------------------------------------------------
# DEFINITION OF THE GUI
#----------------------------------------------------------------------
# MAIN WINDOW
#----------------------------------------------------------------------

our $mw = Tkx::widget->new('.');
$mw->g_wm_title('Lynkeus');
my $icon_path = File::Spec->catdir($Bin, '..', 'data', 'icon.png');
Tkx::image_create_photo( "icon", -file => $icon_path);
$mw->g_wm_iconphoto('icon');

# Resizing
$mw->g_wm_minsize(1000,640);

#----------------------------------------------------------------------
# MENU BARS
#----------------------------------------------------------------------

Tkx::option_add("*tearOff", 0);
our $menu = $mw->new_menu;
$mw->configure(-menu => $menu);

our $search_m  = $menu->new_menu;
our $help_m    = $menu->new_menu;
our $passage_m = $menu->new_menu;
our $export_m  = $menu->new_menu;

$menu->add_cascade
  (
   -menu      => $search_m,
   -label     => $ls{search},
   -underline => 0,
  );
$menu->add_cascade
  (
   -menu      => $help_m,
   -label     => $ls{help},
   -underline => 0,
  );

$search_m->add_command		# index 0
  (
   -label => $ls{new},
   -underline => 0,
   -command => \&clear_search,
   -state => 'disabled'
  );
$search_m->add_command		# index 1
  (
   -label => $ls{save},
   -underline => 0,
   -command => \&save_to_file,
   -state => 'disabled'
  );
$search_m->add_command		# index 2
  (
   -label => $ls{load},
   -underline => 0,
   -command => \&load_from_file,
  );
$search_m->add_separator();
$search_m->add_command		# index 3
  (
   -label => "$ls{pref}...",
   -underline => 0,
   -command => \&edit_configuration,
  );

$search_m->add_command		# index 4
  (
   -label => $ls{quit},
   -underline => 0,
   -command => sub { kill_worker_processes(); $mw->g_destroy }
  );

$help_m->add_command		# index 4
  (
   -label => $ls{manual},
   -underline => 0,
   -command => \&help
  );
$help_m->add_command		# index 4
  (
   -label => $ls{about},
   -underline => 0,
   -command => \&about_lynkeus
  );

sub update_menu {
  $search_m->entryconfigure(0, -state => 'normal'); # new
  $searching					    # save
    ? $search_m->entryconfigure(1, -state => 'disabled')
    : $search_m->entryconfigure(1, -state => 'normal');
  $search_m->entryconfigure(2, -state => 'normal'); # load
}

#------------------------------------------------
# MAIN FRAME
#------------------------------------------------

our $mfrm = $mw->new_ttk__frame
  (
#   -padding => "3 3 12 12",
  );
$mw->g_grid_columnconfigure(0, -weight => 1);
$mw->g_grid_rowconfigure   (0, -weight => 1);

$mfrm->g_grid (-column => 0, -row => 0, -sticky => "nwes");
$mfrm->g_grid_columnconfigure(0, -weight => 0);
$mfrm->g_grid_columnconfigure(1, -weight => 1);
$mfrm->g_grid_rowconfigure   (0, -weight => 1);

#------------------------------------------------
# LEFT HAND SIDE: THE INPUT FRAME
#------------------------------------------------
our $input_frm = $mfrm->new_ttk__frame
  (
   -padding => "5 38 5 10",
  );
$input_frm->g_grid(-column => 0, -row => 0, -sticky => "nw" );

#------------------------------------------------
# Text input widget & scrollbar
#------------------------------------------------
our $input_txt_frm = $input_frm->new_ttk__frame
  (
   -padding => '0 0 0 0',
  );
$input_txt_frm->g_grid(-column => 0, -row => 0, -sticky => "nwes");

our $input_txt = $input_txt_frm->new_tk__text
  (
   -width => 55,
   -height => 10,
   -font   => 'TkTextFont',
   -wrap   => 'word',
   -undo  => 1,
   -padx  => 5,
   -pady  => 5,
   -spacing3 => 2,
  );
# $input_txt->insert('1.0', 'Bitte Text eingeben...');
$input_txt->g_focus();

our $input_scroll = $input_txt_frm->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$input_txt, 'yview']
  );
$input_txt->configure(-yscrollcommand => [$input_scroll, 'set']);
$input_scroll->g___autoscroll__autoscroll() if $autoscroll;

$input_txt->g_grid(-column => 0, -row => 0, -sticky => "nwes");
$input_scroll->g_grid(-column => 1, -row => 0, -sticky => "nwes");

#------------------------------------------------
# Button and Checkboxes
#------------------------------------------------
our $input_bttn_frm = $input_frm->new_ttk__frame
  (
   -padding  => '0 10 0 0',
   # -borderwidth => 10,
   # -relief   => 'raised',
  );
$input_bttn_frm->g_grid(-column => 0, -row => 1, -sticky => "nwes");

# Searchtype
our $st_l = $input_bttn_frm->new_ttk__label
  (
   -text => uc( $ls{search_type} ),
   #  -font  => 'TkSmallCaptionFont'
   # - padding => '0 0 10 0',
  );

our $st_rbt_vbt = $input_bttn_frm->new_ttk__radiobutton
  (
   -text     => $ls{verbatim},
   -variable => \$select_st_lemma,
   -value    => 0,
   );

our $st_rbt_lem = $input_bttn_frm->new_ttk__radiobutton
  (
   -text     => $ls{lemma},
   -variable => \$select_st_lemma,
   -value    => 1,
   );

our $st_cbt_syn = $input_bttn_frm->new_ttk__checkbutton
  (
   -text => $ls{synonyma},
   -command => sub {   },
   -variable => \$select_st_synonyma,
  );

our $st_cbt_cnt = $input_bttn_frm->new_ttk__checkbutton
  (
   -text => $ls{continentia},
   -command => sub {   },
   -variable => \$select_st_continentia,
   );

# Source select and start button
our $si_l = $input_bttn_frm->new_ttk__label
  (
   -text => uc( $ls{search_in} ),
#   -padding => '0 0 10 0',
  );
our $si_cbb = $input_bttn_frm->new_ttk__combobox
  (
   -textvariable => \$select_si_corpus,
   -values => [
	       'TLG',
	       'PHI',
	       'TLG+PHI',
	       "$ls{define_corpus}...",
	      ],
  );
# $si_cbb->state('readonly');
$si_cbb->g_bind
  ("<<ComboboxSelected>>", sub { $si_cbb->selection_clear });

our $input_bttn = $input_bttn_frm->new_ttk__button
  (-text => $ls{search},
   -command => \&begin_search,
   -default => 'active',
  );
our $input_bttn_text = 'search';
$input_bttn->state("!disabled");
#$input_bttn->state("focus");
# $mfrm->g_bind ("<Return>", sub{ $input_bttn->invoke(); } );

# Geometry
$input_bttn_frm->g_grid_columnconfigure(0, -weight => 1);
$input_bttn_frm->g_grid_columnconfigure(1, -weight => 1);
$input_bttn_frm->g_grid_columnconfigure(2, -weight => 1);
$input_bttn_frm->g_grid_rowconfigure(0, -weight => 1);
$input_bttn_frm->g_grid_rowconfigure(1, -weight => 1);
$input_bttn_frm->g_grid_rowconfigure(2, -weight => 1);

$st_l->g_grid      (-column => 0, -row => 0, -sticky => "news", -padx => '4 4');
$st_rbt_vbt->g_grid(-column => 1, -row => 0, -sticky => "news", -padx => '4 4');
$st_rbt_lem->g_grid(-column => 2, -row => 0, -sticky => "news", -padx => '4 4');
$st_cbt_syn->g_grid(-column => 1, -row => 1, -sticky => "news", -padx => '4 4');
$st_cbt_cnt->g_grid(-column => 2, -row => 1, -sticky => "news", -padx => '4 4');
$si_l->g_grid      (-column => 0, -row => 2, -sticky => 'news', -padx => '4 4', -pady => '10 0');
$si_cbb->g_grid    (-column => 1, -row => 2, -sticky => 'news', -padx => '4 4', -pady => '10 0');
$input_bttn->g_grid(-column => 2, -row => 2, -sticky => 'news', -padx => '4 4', -pady => '10 0');

#-----------------------------------------------
# RIGHT HAND SIDE: THE RESULTS NOTEBOOK
#------------------------------------------------

our $results_n = $mfrm->new_ttk__notebook
  (
   -padding => "5 10 5 10"
  );

$results_n->g_grid
  (
   -column => 1,
   -row => 0,
   -sticky => "nwes"
#   -relief => 'flat',
  );

#------------------------------------------------
# Tab 0
#------------------------------------------------
our ($results_tab0, $lemmata_cvs, $lemmata_scroll);
our ($lemmata_frm, $lemmata_frm_handler);
our ($headword_l, $lemmata_l);
our ($lemmata_continue_bttn);
our (@headword_cbb, @headword_cbb_callback);
our (@lemmata_cbb, @lemmata_bttn, @lemmata_bttn_callback);

our ($forms_win, $forms_frm_handler);

$results_tab0 = $results_n->new_ttk__frame;
$results_n->add($results_tab0, -text => $ls{lemmata});

#------------------------------------------------
# Tab 1
#------------------------------------------------
our ($results_tab1, $stats_tw, $stats_scroll, $stats_bttn_frm);
our ($stats_bttn_weight_frm,  $stats_bttn_wrd_frm);
our ($stats_bttn_context_frm, $stats_bttn_threshold_frm);
our ($stats_show_bttn, $results_bttn);
our ($stats_wrd_l, $stats_add_bttn, $stats_edit_bttn, $stats_rm_bttn);
our ($stats_weight_l, $stats_weight_sb);
our ($stats_threshold_l, $stats_threshold_sb);
our ($stats_context_l, $stats_context_cbb, $stats_context_sb);
$results_tab1 = $results_n->new_ttk__frame
  (-padding => '0 0 0 0'); 
$results_n->add($results_tab1, -text => $ls{statistics});

# WIDGET DEFINITIONS
# Style and appearence of the treeview widget
Tkx::ttk__style_configure
  (
   "Treeview",
   # -font => [-weight => 'bold'],
   # -background => 'yellow',
   -rowheight => 20,
   -padding => '10 30 10 10'
  );
Tkx::ttk__style_configure
  (
   "Heading",
   -foreground => '#3E7804',
   -foreground => 'green',
   # -font => [-weight => 'bold']
   # -padding => '50 20 20 20'
  );

# Treeview
$stats_tw = $results_tab1->new_ttk__treeview
  (
   -padding => '5 10 5 19',
   -height => 23,
  );

$stats_tw->configure(-columns => "hits weight");
$stats_tw->column("#0", -width => 200, -anchor => "w");
$stats_tw->heading("#0", -text => $ls{search_term}, -anchor => "w");
$stats_tw->column("hits", -width => 100, -anchor => "w");
$stats_tw->heading("hits", -text => $ls{numberofhits}, -anchor => "w");
$stats_tw->column("weight", -width => 100, -anchor => "w");
$stats_tw->heading("weight", -text => $ls{weight}, -anchor => "w");

# Scrollbar
$stats_scroll = $results_tab1->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$stats_tw, 'yview']
  );
$stats_tw->configure(-yscrollcommand => [$stats_scroll, 'set']);
$stats_scroll->g___autoscroll__autoscroll() if $autoscroll;

# Buttons
$stats_bttn_frm = $results_tab1->new_ttk__frame
  (
   -padding => '10 0 10 0',
   # -relief => 'sunken'
  );

$stats_show_bttn = $stats_bttn_frm->new_ttk__button
  (-text => $ls{view},
   -command => \&view_single_results,
   -state => 'disabled',
  );



$stats_bttn_wrd_frm = $stats_bttn_frm->new_ttk__frame
  (
   -borderwidth => '2',
   -relief => 'raised',
   -padding => '5 2 5 2',
  );
$stats_wrd_l = $stats_bttn_wrd_frm->new_ttk__label
  (
   -text => uc( $ls{search_term} ),
   -anchor => 'center',
  );
$stats_add_bttn = $stats_bttn_wrd_frm->new_ttk__button
  (-text => $ls{add},
   -command => \&add_words,
   -state => 'disabled',
  );
$stats_edit_bttn = $stats_bttn_wrd_frm->new_ttk__button
  (-text => $ls{edit},
   -command => \&edit_words,
   -state => 'disabled',
  );
$stats_rm_bttn = $stats_bttn_wrd_frm->new_ttk__button
  (-text => $ls{remove},
   -command => \&rm_words,
   -state => 'disabled',
  );



$stats_bttn_weight_frm = $stats_bttn_frm->new_ttk__frame
  (
   -borderwidth => '2',
   -relief => 'raised',
   -padding => '5 2 5 2',
  );
$stats_weight_l = $stats_bttn_weight_frm->new_ttk__label
  (
   -text => uc( $ls{weight} ),
   -anchor => 'center',
  );
$stats_weight_sb = $stats_bttn_weight_frm->new_ttk__spinbox
  (
   -from => 0,
   -to   => 100.0,
   -textvariable => \$weight,
   -state => 'disabled',
   -command => \&empty_weight,
   -width => 4,
   # without this command, the spinbox displays faulty numbers when
   # multiple entries are selected
   -validate => 'all',
   -validatecommand => [ \&is_numeric, Tkx::Ev('%P')]
  );


$stats_bttn_context_frm = $stats_bttn_frm->new_ttk__frame
  (
   -borderwidth => '2',
   -relief => 'raised',
   -padding => '5 2 5 2',
  );
$stats_context_l = $stats_bttn_context_frm->new_ttk__label
  (
   -text => uc( $ls{context} ),
   -anchor => 'center',
  );
$stats_context_sb = $stats_bttn_context_frm->new_ttk__spinbox
  (
   -from => 1.0,
   -to   => 100.0,
   -textvariable => \$context,
   -state => 'normal',
   -width => 4,
   -command => \&context_sb_callback,
   -validate => 'all',
   -validatecommand => [ \&is_numeric, Tkx::Ev('%P')]
  );
$stats_context_cbb = $stats_bttn_context_frm->new_ttk__combobox
  (
   -textvariable => \$context_type_str,
   -values => \@context_types_str,
   -width => 10,
  );

$stats_bttn_threshold_frm = $stats_bttn_frm->new_ttk__frame
  (
   -borderwidth => '2',
   -relief => 'raised',
   -padding => '5 2 5 2',
  );
$stats_threshold_l = $stats_bttn_threshold_frm->new_ttk__label
  (
   -text => uc( $ls{threshold} ),
   -anchor => 'center',
  );
$stats_threshold_sb = $stats_bttn_threshold_frm->new_ttk__spinbox
  (
   -from => 1.0,
   -to   => 100.0,
   -textvariable => \$threshold,
   -state => 'normal',
   -width => 4,
   -validate => 'all',
   -validatecommand => [ \&is_numeric, Tkx::Ev('%P')]
  );

$results_bttn = $stats_bttn_frm->new_ttk__button
  (-text => $ls{result},
   -command => \&begin_evaluation,
   -state => 'normal',
  );

# BINDINGS
$stats_tw->g_bind( '<<TreeviewSelect>>', \&update_selection );
$stats_tw->g_bind( '<Escape>', \&rm_selection );
$stats_tw->g_bind( '<Return>', \&begin_evaluation );
# $stats_tw->g_bind( '<Control-Z>', \&redo_words );

$stats_weight_sb->g_bind( '<Return>',      \&set_weight_selection );
$stats_weight_sb->g_bind( '<Escape>',      \&update_selection );
$stats_weight_sb->g_bind( '<<Increment>>', \&increment_weight_selection );
$stats_weight_sb->g_bind( '<<Decrement>>', \&decrement_weight_selection );

Tkx::trace("add", "variable", \$context, "write", \&context_sb_callback);

# GEOMETRY
# results_tab1
$results_tab1->g_grid_columnconfigure (0, -weight => 1);
$results_tab1->g_grid_columnconfigure (1, -weight => 0);
$results_tab1->g_grid_columnconfigure (2, -weight => 0);
$results_tab1->g_grid_rowconfigure (0, -weight => 1);

$stats_tw->g_grid      (-column => 0, -row => 0, -sticky => "nwes");
$stats_scroll->g_grid  (-column => 1, -row => 0, -sticky => "nwes");
$stats_bttn_frm->g_grid(-column => 2, -row => 0, -sticky => 'nwes');

# stats_bttn_frm
$stats_bttn_frm->g_grid_columnconfigure(0, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (0, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (1, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (2, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (3, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (4, -weight => 1);
$stats_bttn_frm->g_grid_rowconfigure   (5, -weight => 1);
$stats_show_bttn->g_grid         (-column => 0, -row => 0, -pady => '0', -sticky => 'we');
$stats_bttn_wrd_frm->g_grid      (-column => 0, -row => 1, -pady => '0', -sticky => 'we');
$stats_bttn_weight_frm->g_grid   (-column => 0, -row => 2, -pady => '0', -sticky => 'we');
$stats_bttn_context_frm->g_grid  (-column => 0, -row => 3, -pady => '0', -sticky => 'we');
$stats_bttn_threshold_frm->g_grid(-column => 0, -row => 4, -pady => '0', -sticky => 'we');
$results_bttn->g_grid            (-column => 0, -row => 5, -pady => '0', -sticky => 'we');

# stats_bttn_wrd_frm
$stats_bttn_wrd_frm->g_grid_columnconfigure (0, -weight => 1);
$stats_wrd_l->g_grid    (-column => 0, -row => 0, -pady => 5, -sticky => 'we');
$stats_add_bttn->g_grid (-column => 0, -row => 1, -pady => 5, -sticky => 'we');
$stats_edit_bttn->g_grid(-column => 0, -row => 2, -pady => 5, -sticky => 'we');
$stats_rm_bttn->g_grid  (-column => 0, -row => 3, -pady => 5, -sticky => 'we');

# stats_bttn_weight_frm
$stats_bttn_weight_frm->g_grid_columnconfigure (0, -weight => 1);
$stats_weight_l->g_grid (-column => 0, -row => 0, -pady => 5, -sticky => 'we');
$stats_weight_sb->g_grid(-column => 0, -row => 1, -pady => 5, -sticky => 'we');

# stats_bttn_context_frm
$stats_bttn_context_frm->g_grid_columnconfigure (0, -weight => 1);
$stats_bttn_context_frm->g_grid_columnconfigure (1, -weight => 1);
$stats_context_l->g_grid  (-column => 0, -row => 0, -pady => 5, -sticky => 'we', -columnspan => 2);
$stats_context_sb->g_grid (-column => 0, -row => 1, -pady => 5, -padx => 2, -sticky => 'we');
$stats_context_cbb->g_grid(-column => 1, -row => 1, -pady => 5, -padx => 2, -sticky => 'we');

# stats_bttn_threshold_frm
$stats_bttn_threshold_frm->g_grid_columnconfigure (0, -weight => 1);
$stats_threshold_l->g_grid (-column => 0, -row => 0, -pady => 5, -sticky => 'we');
$stats_threshold_sb->g_grid(-column => 0, -row => 1, -pady => 5, -sticky => 'we');


#------------------------------------------------
# Tab 2
#------------------------------------------------
our ($results_tab2, $results_txt, $results_scroll);
$results_tab2 = $results_n->new_ttk__frame; 
$results_n->add($results_tab2, -text => $ls{result});

$results_txt = $results_tab2->new_tk__text
  (
   -width  => 85,
   -height => 30,
   -font   => 'TkTextFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   #  -bg     => 'gray85',
   -border => 0,
   -state => 'disabled',
   -spacing3 => 2,
   -exportselection => 1,
  );
$results_txt->g_bind('<Configure>', \&update_separator_width);
# $results_txt->configure(-state => 'disabled');

$results_scroll = $results_tab2->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$results_txt, 'yview']
  );
$results_txt->configure(-yscrollcommand => [$results_scroll, 'set']);
$results_scroll->g___autoscroll__autoscroll() if $autoscroll;

$results_tab2->g_grid_columnconfigure(0, -weight => 1);
$results_tab2->g_grid_columnconfigure(1, -weight => 0);
$results_tab2->g_grid_rowconfigure   (0, -weight => 1);
$results_txt->g_grid   (-column => 0, -row => 0, -sticky => "nwes");
$results_scroll->g_grid(-column => 1, -row => 0, -sticky => "nwes");



#------------------------------------------------
# Tabs configuration
#------------------------------------------------
# Hide Tabs on startup
$results_n->tab('0', -state => 'hidden');
$results_n->tab('1', -state => 'hidden');
$results_n->tab('2', -state => 'hidden');

#----------------------------------------------------------------------
# WINDOW FUNCTIONS
#----------------------------------------------------------------------
sub fullscreen{
  $mw->g_wm_attributes(-fullscreen)
    ? $mw->g_wm_attributes(-fullscreen => 0)
    : $mw->g_wm_attributes(-fullscreen => 1);
}

#-----------------------------------------------------------------------
# KEY BINDINGS
#-----------------------------------------------------------------------
# $mw->g_bind("<Return>", sub { $input_bttn->invoke() });
$mw->g_bind('<Control-Return>', sub { $input_bttn->invoke() } );

$mw->g_bind('<F1>',  sub { Tkx::update_idletasks(); say $mw->g_wm_geometry() });
$mw->g_bind('<F11>', \&fullscreen);
$mw->g_bind('<F2>', sub { kill USR1 => $pid[$_] for 0..$CORES });
#-----------------------------------------------------------------------
# EVENT BINDINGS
#-----------------------------------------------------------------------
# $mw->g_bind('<Destroy>', \&kill_worker_processes );
$mw->g_wm_protocol("WM_DELETE_WINDOW" => sub{ kill_worker_processes(); $mw->g_destroy() });

#----------------------------------------------------------------------
# Increase and decrease fonts
sub set_text_font {
  my $text_font_size = $normal_size;
  return sub {
    my $num = shift;
    my $active = Tkx::focus();
    $text_font_size = ($text_font_size + $num > 5)
      ? $text_font_size + $num
      : 5;
    if ($gentium_available) {
      Tkx::i::call("$active", 'configure', "-font", [-family => 'Gentium', -size => "$text_font_size"]);
    }
    else {
      Tkx::i::call("$active", 'configure', "-font", [-size => "$text_font_size"]);
    }
  }
}
our $input_txt_scale = set_text_font();
$input_txt->g_bind('<Control-plus>',        [\&$input_txt_scale, '1'] );
$input_txt->g_bind('<Control-KP_Add>',      [\&$input_txt_scale, '1'] );
$input_txt->g_bind('<Control-minus>',       [\&$input_txt_scale, '-1'] );
$input_txt->g_bind('<Control-KP_Subtract>', [\&$input_txt_scale, '-1'] );

our $results_txt_scale   = set_text_font();
$results_txt->g_bind('<Control-plus>',        [\&$results_txt_scale, '1'] );
$results_txt->g_bind('<Control-KP_Add>',      [\&$results_txt_scale, '1'] );
$results_txt->g_bind('<Control-minus>',       [\&$results_txt_scale, '-1'] );
$results_txt->g_bind('<Control-KP_Subtract>', [\&$results_txt_scale, '-1'] );

#----------------------------------------------------------------------
# KNOWN TAGS FOR TEXT WIDGETS
#----------------------------------------------------------------------
# input_txt
if ($gentium_available) {
  $input_txt->tag_configure
    ("searching",
     #  -background => "yellow",
     -foreground => '#3E7804',
     -font => [-family => 'Gentium', -weight => 'bold'],
     # -font => [-slant => 'italic'],
     # -weight => 'bold',
     # -relief => "raised"
    );
}
else {
  $input_txt->tag_configure
    ("searching",
     -foreground => '#3E7804',
     -font => [-weight => 'bold'],
    );
}
$input_txt->tag_configure
  ("blacklist",
   -foreground => 'gray',
  );
$input_txt->tag_configure
  ("aborted",
   -foreground => 'gray',
   # -overstrike => 1,
  );

# results_txt
$results_txt->tag_configure
  ("header",
   -foreground => '#3E7804',
  );
$results_txt->tag_configure
  ("matched",
   -background => "yellow",
  );
$results_txt->tag_configure
  ("info",
   -foreground => 'gray',
   -spacing1 => 5,
  );

#------------------------------------------------
# FINISH STARTUP

# $st_rbt_vbt->state('disabled');
# $st_rbt_lem->state('disabled');
$st_cbt_syn->state('disabled');
$st_cbt_cnt->state('disabled');

# Load the first file given on the command line
if (@ARGV) {
  my $arg = shift @ARGV;
  if (-f $arg and $arg =~ /\.lyn$/) {
    load($arg);
  }
  else { error("$ls{load_failure} $arg!") }
  warn "Lynkeus can only load one file at a time!\n" if @ARGV;
}


#------------------------------------------------
# THE MAIN SUBROUTINES
#------------------------------------------------
#------------------------------------------------
# PART 1: PROCESSING THE INPUT TEXT
#------------------------------------------------

#------------------------------------------------
# STEP 1: Set up variables and widgets

sub begin_search {
  $searching = 1; update_menu();
  # Empty search data
  $results_txt->delete('1.0', 'end');
  $results_n->tab('2', -state => 'hidden');
  $lemmata_cvs->g_destroy() if $lemmata_cvs;
  # We need to clear also the other global variables connected with Tab 0
  undef @lemmata_bttn;
  undef $lemmata_continue_bttn;
  # clear menus associated with $results_txt
  clear_output_menus();

  # get the selection of the search type and corpus
  $st_lemma       = $select_st_lemma;
  $st_synonyma    = $select_st_synonyma;
  $st_continentia = $select_st_continentia;
  $si_corpus      = $select_si_corpus;

  # disable the switches
  $st_rbt_vbt->state('disabled');
  $st_rbt_lem->state('disabled');
  # $st_cbt_syn->state('disabled');
  # $st_cbt_cnt->state('disabled');

  if ($st_lemma) {
    $results_n->tab('1', -state => 'hidden');
    $results_n->tab('0', -state => 'normal');
    $results_n->select('0');
  }
  else {
    $results_n->tab('0', -state => 'hidden');
    $results_n->tab('1', -state => 'normal');
    $results_n->select('1');
  }
  @words = ();
  %deleted_passages = ();
  %elided_passages  = ();
  

  $input_bttn->configure
    (
     -text => $ls{cancel},
     -command => sub { $interrupt = 1 },
    );
  $input_bttn_text = 'cancel';
  $input_txt->configure(-state => "disabled");

  Tkx::after(5, \&get_input)
}

sub clear_output_menus {
  if ($menu->index('end') == 3) {
    $menu->delete(1,2);
    $passage_m->delete(0,2);
    $export_m->delete(0,2);
  }
}

#------------------------------------------------
# STEP 2a: Get and preprocess user input
sub get_input {
  end_search() and return if $interrupt;

  $input_str = $input_txt->get('1.0', 'end');

  # Abort if $input_txt is empty
  if ($input_str !~ /\w/) {
    error($ls{error_empty});
    end_search();
    edit_search();
    return;
  }

  # Remember the original lines (needed for @positions)
  my @input_lines = split /\n/, $input_str;

  # Delete leading an trailing whitespace, populate @input_words
  $input_str =~ s/^\s*//;
  $input_str =~ s/\s*$//;
  my @input_words = split /\s+/, $input_str;
  say "Input words:";
  say for @input_words;
  say "";

  # Preprocess words
  # Remove interpunctation, make all lowercase beta code
  @input_words =  map
    {
      $_ =~ s/^[(<\[{]//;
      $_ =~ s/[\.··\?\])>},;·]$//;
      lc $_;
    }
    @input_words;

  # VERBATIM SEARCH ONLY:
  # Remove duplicates, but remember the times we have seen this word
  my %seen = ();
  unless ($st_lemma) {
    @input_words =  grep { ! $seen{ $_ }++ } @input_words;
  }

  # Process words, populate @words array
  my $current_line         = 0;
  my $current_line_offset  = undef;
 WORD: for my $index (0..$#input_words) {
    my $word = $input_words[$index];
    # Remove words found on the backlist
    for (@blacklist) {
      # Make comparison diacritics insensitive
      my $w = $word =~ tr#/\\=()|\*##rd;
      if ( $Collator->eq($w, $_) ) {
	# Get indices of the word and make it grey
	my @positions = get_positions($word, \@input_lines, \$current_line, \$current_line_offset);
	while (@positions) {
	  my $line  = shift @positions;
	  my $begin = shift @positions;
	  my $end   = shift @positions;
	  $input_txt->tag_add("blacklist", "$line.$begin", "$line.$end");
	}
	next WORD;
      }
    }

    # VERBATIM SEARCH: Get indices of the words in the original string
    my @positions;
    unless ($st_lemma) {
      @positions = get_positions($word, \@input_lines);
      die
	"I expected $seen{ $word } hits for $word but found only "
	. ( @positions / 3 ) . " hit for $word at positions @positions"
	if $seen{ $word } * 3 != @positions;
    }
    else {
      @positions = get_positions
	($word, \@input_lines, \$current_line, \$current_line_offset);
      $seen{$word} = 1;
    }

    # populate @words array;
    my %hash =
      (
       word       => $word,
       times_seen => $seen{ $word },
       positions  => \@positions,
      );
    push @words, \%hash;
  }
  print Dumper(@words);

  if ($st_lemma) { Tkx::after( 10, [\&setup_lemma_search, 0] ); }
  else           { Tkx::after( 10, [\&finish_setup, 0] ); }
}

#------------------------------------------------
# STEP 2: Finish data setup
sub finish_setup {
  # set up the default threshold
  $threshold = (@words / 2 > 2)
    ? int ( (@words * 10) / $default_threshold_percent)
    : 2;

  # setup progress bars, status treeview, and the status buttons
  my $total = @words;
  make_progress_bars($total, $ls{total});
  # make_stats_tw();
  # clear stats_tw
  my @stats_tw_items = $stats_tw->children('');
  $stats_tw->delete("@stats_tw_items");

  Tkx::after(5, \&setup_searches)
}

#------------------------------------------------
# Step 2c: Helper functions
sub get_positions {
  my ($word, $input_lines, $current_line, $current_line_offset) = @_;
  my @positions;
  # $word = lc Diogenes::UnicodeInput->unicode_greek_to_beta($word);
  my $l = 0;

  # VERBATIM SEARCH
  unless ($st_lemma) {
    for my $line (@$input_lines) {
      $l++;
      # $line = lc Diogenes::UnicodeInput->unicode_greek_to_beta($line);
      while ($line =~ m/(?:^|\s+|[\[(<])(\Q$word\E)(?=$|\s+|[\])>.,··;?!])/gi) {
	push @positions, $l;
	push @positions, $-[1];
	push @positions, $+[1];
      }
      say "$word: @positions";
    }
  }

  # LEMMA SEARCH
  else {
    my $line = $input_lines->[$$current_line];
    pos($line) = $$current_line_offset;
    say $line;

    while (1) {
      if ($line =~ m/(?:^|\s+|[\[(<])(\Q$word\E)(?=$|\s+|[\])>.,··;?!])/gi) {
	push @positions, $$current_line + 1;
	push @positions, $-[1];
	push @positions, $+[1];
	$$current_line_offset = $+[1];
	last;
      }
      else {
	$$current_line++;
	die "Could not find $word!" if $$current_line > @$input_lines;
	$line = $input_lines->[$$current_line];
	pos($line) = undef;
	$$current_line_offset = 0;
      }
    }
    say "$word: @positions";
  }
  return @positions;
}

sub make_progress_bars {
  my $total = shift;
  my $label = shift // '';
  $label .= ': ' if $label;

  $progress_frm = $input_frm->new_ttk__frame
      (
       -padding => "0 20 0 10",
      );
  $progress_frm->g_grid(-column => 0, -row => 2, -sticky => "we");
  $progress_frm->g_grid_columnconfigure(0, -weight => 1);
  $progress_frm->g_grid_rowconfigure(0, -weight => 1);

  # total progress
  $progress_t_frm = $progress_frm->new_ttk__frame
      (
       -padding => "0 0 0 10",
      );
  $progress_t_frm->g_grid(-column => 0, -row => 0, -sticky => "we");
  $progress_t_frm->g_grid_columnconfigure(0, -weight => 1);
  $progress_t_frm->g_grid_columnconfigure(1, -weight => 1);
  $progress_t_frm->g_grid_rowconfigure(0, -weight => 1);

  $progress_t_l = $progress_t_frm->new_ttk__label
      (
       -text => "$label" . "0/$total",
       #  -padding => '0 0 10 0',
      );
  $progress_t_bar = $progress_t_frm->new_ttk__progressbar
    (
     -orient => 'horizontal',
     -length => 280,
     -maximum => ( $total ),
     -mode => 'determinate'
    );
  $progress_t_l  ->g_grid(-column => 0, -row => 0, -sticky => "w");
  $progress_t_bar->g_grid(-column => 1, -row => 0, -sticky => "e");
}

sub update_progress_bar {
  my $number = shift;
  my $total = shift;
  my $label = shift // '';
  $label .= ': ' if $label;

  $progress_t_bar->configure(-value => $number);
  $progress_t_l  ->configure(-text => "$label" . "$number/$total");
}

sub make_word_progress_bar {
  my $w = shift;
  my $number = ++$progress_w_cnt;

  # frame
  $words[$w]{progress}{frm} = $progress_frm->new_ttk__frame
    (-padding => "0 2 0 2");
  $words[$w]{progress}{frm}->g_grid
    (-column => 0, -row => $number + 1, -sticky => "we");
  $words[$w]{progress}{frm}->g_grid_columnconfigure(0, -weight => 1);
  $words[$w]{progress}{frm}->g_grid_columnconfigure(1, -weight => 1);
  $words[$w]{progress}{frm}->g_grid_rowconfigure(0, -weight => 1);
  $words[$w]{progress}{frm}->g_grid_rowconfigure(1, -weight => 1);

  # contents
  my $total =  $words[$w]{steps};
  my $word =   $words[$w]{word};
  $words[$w]{progress}{bar} = $words[$w]{progress}{frm}->new_ttk__progressbar
    (
     -orient => 'horizontal',
     -length => 280,
     -mode => 'determinate',
     -maximum => $total,
    );
  $words[$w]{progress}{lbl} = $words[$w]{progress}{frm}->new_ttk__label
    (-text => "$word");
    # (-text => "$word: 0/$total");
  $words[$w]{progress}{lbl}->g_grid(-column => 0, -row => 0, -sticky => "w", -padx => [4, 10]);
  $words[$w]{progress}{bar}->g_grid(-column => 1, -row => 0, -sticky => "e");

  # info callback
  my $callback = sub { word_progress_info($w) };
  $words[$w]{progress}{bar}->g_bind("<ButtonPress-1>", $callback );
  $words[$w]{progress}{lbl}->g_bind("<ButtonPress-1>", $callback );
}

sub word_progress_info {
  my $w = shift;
  if ( exists $words[$w]{progress}{info} ) {
    $words[$w]{progress}{info}{frm}->g_destroy();
    delete $words[$w]{progress}{info};
  }
  else {
    # frame
    $words[$w]{progress}{info}{frm} =
      $words[$w]{progress}{frm}->new_ttk__frame
      (-padding => "0 2 0 2");
    $words[$w]{progress}{info}{frm}->g_grid
      (-column => 0, -row => 1, -columnspan => 2,  -sticky => "we");
    $words[$w]{progress}{info}{frm}->g_grid_columnconfigure
      (0, -weight => 1);
    $words[$w]{progress}{info}{frm}->g_grid_columnconfigure
      (1, -weight => 1);
    $words[$w]{progress}{info}{frm}->g_grid_columnconfigure
      (2, -weight => 1);
    $words[$w]{progress}{info}{frm}->g_grid_columnconfigure
      (3, -weight => 1);

    # core info
    for my $chunk ( sort numerically keys %{ $words[$w]{processing} } ) {
    $words[$w]{progress}{info}{frm}->g_grid_rowconfigure
      ($chunk, -weight => 1);

      # Chunk
      $words[$w]{progress}{info}{chunk}[$chunk]{chunk} =
	$words[$w]{progress}{info}{frm}->new_ttk__label
	(-text => "$chunk:");
      $words[$w]{progress}{info}{chunk}[$chunk]{chunk}->g_grid
	(-column => 0, -row => $chunk, -sticky => "w", -padx => [4, 10]);

      # corpus number
      my $tlg_nr = $words[$w]{processing}{$chunk}{active_file};
      my $finished_files = $words[$w]{processing}{$chunk}{finished_files} // 0;
      my $total_files  = $words[$w]{processing}{$chunk}{total} // 0;
      my $corpus = uc($si_corpus);
      $words[$w]{progress}{info}{chunk}[$chunk]{tlg} =
	$words[$w]{progress}{info}{frm}->new_ttk__label
	(-text => "$corpus: $tlg_nr ($finished_files/$total_files)");
      $words[$w]{progress}{info}{chunk}[$chunk]{tlg}->g_grid
	(-column => 1, -row => $chunk, -sticky => "w", -padx => [10, 10]);

      my $progress = 0;
      my $total = 0;
      # active search pattern && progress bar
      if ($st_lemma) {
	my $pass = $words[$w]{processing}{$chunk}{pass} // 0;
	my $final_pass = @{ $words[$w]{forms} };
	if ($final_pass > 1) {
	  my $passf = sprintf "%3d", $pass;
	  $words[$w]{progress}{info}{chunk}[$chunk]{pattern} =
	    $words[$w]{progress}{info}{frm}->new_ttk__label
	    (-text => "$passf/$final_pass");
	  $words[$w]{progress}{info}{chunk}[$chunk]{pattern}->g_grid
	    (-column => 2, -row => $chunk, -sticky => "e", -padx => [10, 10]);
	}

	$progress = ($finished_files * $final_pass) + $pass;
	$total    = $total_files * $final_pass;
      }
      # only progress bar
      else {
	$progress = $finished_files;
	$total    = $total_files;
      }

      # progress bar
      $words[$w]{progress}{info}{chunk}[$chunk]{bar} =
	$words[$w]{progress}{info}{frm}->new_ttk__progressbar
	(
	 -orient => 'horizontal',
	 -length => 200,
	 -mode => 'determinate',
	 -value => $progress,
	 -maximum => $total,
	);
      $words[$w]{progress}{info}{chunk}[$chunk]{bar}->g_grid
	(-column => 3, -row => $chunk, -sticky => "we", -padx => [0, 0]);
    }
    # pattern button
    if ($st_lemma) {
      my $pattern_callback = sub { edit_patterns($w) };
      $words[$w]{progress}{info}{pattern_w} =
	$words[$w]{progress}{info}{frm}->new_ttk__button
	(-text => "$ls{pattern}...",
	 -command => $pattern_callback,
	);
      $words[$w]{progress}{info}{pattern_w}->g_grid
	(-column => 1, -columnspan => 2,
	 -row => $CORES + 2, -sticky => "we", -pady => [5, 5]);
    }

    # cancel button
    my $cancel_callback = sub { cancel_search($w) };
    $words[$w]{progress}{info}{cancel} =
      $words[$w]{progress}{info}{frm}->new_ttk__button
      (-text => $ls{cancel},
       -command => $cancel_callback,
      );
    $words[$w]{progress}{info}{cancel}->g_grid
      (-column => 3, -row => $CORES + 2, -sticky => "we", -pady => [5, 5]);
  }
}

sub cancel_search {
  my $w = shift;
  $words[$w]{abort} = 1;
}

sub make_word_progress_info_chunk {
  my $w = shift;
  my $chunk = shift;
    return unless exists $words[$w]{progress}{info};

  # code below copied from previous function
  # TODO: common subfunctions!
  $words[$w]{progress}{info}{chunk}[$chunk]{chunk} =
    $words[$w]{progress}{info}{frm}->new_ttk__label
    (-text => "$chunk:");
  $words[$w]{progress}{info}{chunk}[$chunk]{chunk}->g_grid
    (-column => 0, -row => $chunk, -sticky => "w", -padx => [4, 10]);

  # corpus number
  my $tlg_nr = $words[$w]{processing}{$chunk}{active_file} // '';
  my $finished_files = $words[$w]{processing}{$chunk}{finished_files} // 0;
  my $total_files  = $words[$w]{processing}{$chunk}{total} // 0;
  my $corpus = uc($si_corpus);
  $words[$w]{progress}{info}{chunk}[$chunk]{tlg} =
    $words[$w]{progress}{info}{frm}->new_ttk__label
    (-text => "$corpus: $tlg_nr ($finished_files/$total_files)");
  $words[$w]{progress}{info}{chunk}[$chunk]{tlg}->g_grid
    (-column => 1, -row => $chunk, -sticky => "w", -padx => [10, 10]);

  my $progress = 0;
  my $total = 0;
  # active search pattern && progress bar
  if ($st_lemma) {
    my $pass = $words[$w]{processing}{$chunk}{pass} // 0;
    my $final_pass = @{ $words[$w]{forms} };
    if ($final_pass > 1) {
      my $passf = sprintf "%3d", $pass;
      $words[$w]{progress}{info}{chunk}[$chunk]{pattern} =
	$words[$w]{progress}{info}{frm}->new_ttk__label
	(-text => "$passf/$final_pass");
      $words[$w]{progress}{info}{chunk}[$chunk]{pattern}->g_grid
	(-column => 2, -row => $chunk, -sticky => "e", -padx => [10, 10]);
    }

    $progress = ($finished_files * $final_pass) + $pass;
    $total    = $total_files * $final_pass;
  }
  # only progress bar
  else {
    print "Progress ";
    say $progress = $finished_files;
    print "Total ";
    say $total    = $total_files;
  }

  # progress bar
  $words[$w]{progress}{info}{chunk}[$chunk]{bar} =
    $words[$w]{progress}{info}{frm}->new_ttk__progressbar
	(
	 -orient => 'horizontal',
	 -length => 200,
	 -mode => 'determinate',
	 -value => $progress,
	 -maximum => $total,
	);
  $words[$w]{progress}{info}{chunk}[$chunk]{bar}->g_grid
    (-column => 3, -row => $chunk, -sticky => "we", -padx => [0, 0]);
}

sub update_word_progress_bars {
  my $w = shift;
  my $word = $words[$w]{word};
  my $steps = $words[$w]{steps} || 0;

  # sum up the progress of the individual chunks
  my $progress = 0;
  for my $chunk (keys %{ $words[$w]{processing} }){
    my $pass = $words[$w]{processing}{$chunk}{pass} // 0;
    my $finished_files = $words[$w]{processing}{$chunk}{finished_files} // 0;
    my $chunk_progress = ($st_lemma)
      ? $finished_files * @{ $words[$w]{forms} }
      : $finished_files;
    $chunk_progress += $pass;
    $progress += $chunk_progress;
  }
  my $total =  $words[$w]{steps};

  $words[$w]{progress}{bar}->configure(-value => $progress);
  $words[$w]{progress}{bar}->configure(-maximum => $steps);
  $words[$w]{progress}{lbl}->configure(-text => "$word");
  # $words[$w]{progress}{lbl}->configure(-text => "$word: $progress/$total");

  # info frame
  if  ( exists $words[$w]{progress}{info} ) {
    for my $chunk ( sort numerically keys %{ $words[$w]{processing} } ) {
      # corpus number
      my $tlg_nr = $words[$w]{processing}{$chunk}{active_file} // '';
      my $finished_files = $words[$w]{processing}{$chunk}{finished_files} // 0;
      my $total_files  = $words[$w]{processing}{$chunk}{total} // 0;
      my $corpus = uc($si_corpus);
      $words[$w]{progress}{info}{chunk}[$chunk]{tlg}->configure
	(-text => "$corpus: $tlg_nr ($finished_files/$total_files)");

      my $progress = 0;
      my $total = 0;
      # active search pattern && progress bar
      if ($st_lemma) {
	my $pass = $words[$w]{processing}{$chunk}{pass} // 0;
	my $final_pass = @{ $words[$w]{forms} };
	if ($final_pass > 1) {
	  my $passf = sprintf "%3d", $pass;
	  $words[$w]{progress}{info}{chunk}[$chunk]{pattern}->configure
	    (-text => "$passf/$final_pass");
	}
	$progress = ($finished_files * $final_pass) + $pass;
      }
      # only progress bar
      else {
	$progress = $finished_files;
      }

      # progress bar
      $words[$w]{progress}{info}{chunk}[$chunk]{bar}->configure
	(-value => $progress);
    }
  }
}

sub delete_word_progress_bar {
  # delete progress bar, delete key for the progress core table
  my $w = shift;
  $words[$w]{progress}{frm}->g_destroy();
}

sub update_stats_tw {
  my $index = shift;
  my $word = $words[$index]{word};
  my $hits = $words[$index]{hits};
  my $text = (!$st_lemma)
    ? $word
    : $words[$index]{lemma};
  my $weight = 1;
   $stats_tw->insert
     (
      "",
      "$index",
      -id     => "$word.$index",
      -open   => "false",
      -text   => "$text",
      -values => "$hits $weight",
 #     -style  => "Row.Treeview",
     );
}

#------------------------------------------------
# STEP 3: Manage searches

sub setup_searches {
  my $queue      = [];
  my $processing = {};
  my $finished =   {};
  my $idle_cores = [0..$CORES];
  $progress_w_cnt = 0;

  my @author_nums = make_author_list();
  my $type = shift @author_nums;
  my $corenum = $CORES + 1;
  my $step = int @author_nums / $corenum;
  my $modulo = @author_nums % $corenum;

  # initialize the results keys in our word hash
  for my $word(0..$#words) {
    ${ $words[$word]{result} }     = '';
    $words[$word]{hits}            = 0;
    $words[$word]{seen_all}        = {};
    $words[$word]{match_start_all} = {};
    $words[$word]{not_printed}     = {};

    # delete the restart flag if it was set
    delete $words[$word]{restart} if exists $words[$word]{restart};
  }

  # Distribute the selected authors into chunks
  for my $word (0..$#words) {
    # get the patterns for each word, compute the number of steps
    # required to finish the whole search for one word
    my @patterns = make_pattern_list($word);
    $words[$word]{steps} = (@author_nums) * @patterns;
    # local copies to be used destructive in each iteration
    my @core_authors = @author_nums;
    my $rest = $modulo;
    # intitialize the $finished hash
    $finished->{$word} = {};

    for my $chunk (1..$corenum) {
      if ($step or $rest) {
	my @author_chunk;
	if ($rest) {
	  @author_chunk = @core_authors[ 0 .. $step ];
	  @core_authors = @core_authors[ ($step + 1) .. $#core_authors ];
	  $rest--;
	}
	elsif ($step) {
	  @author_chunk = @core_authors[ 0 .. ($step - 1) ];
	  @core_authors = @core_authors[ $step .. $#core_authors ];
	}

	my %hash;
	$hash{word}     = $word;
	$hash{chunk}    = $chunk;
	$hash{type}     = $type;
	$hash{patterns} = \@patterns;
	$hash{authors}  = \@author_chunk;
	push @$queue, \%hash;
      }
    }
  }

  $finished->{last} = ($corenum > @author_nums)
    ? @author_nums
    : $corenum;
  $finished->{total} = 0;

  Tkx::after( 10, [\&manage_searches,
		   $queue, $processing, $finished, $idle_cores] );
}

sub manage_searches {
  # $queue, $idle_cores: arrayrefs, $processing: $hashref
  my ($queue, $processing, $finished, $idle_cores) = @_;

  # we have to add here some specific cleanup for this function
  if ($interrupt) {
    abort_searches($queue, $processing);
    return;
  }
  # abort searches as requested
  for my $word (0..$#words) {
    if ( exists $words[$word]{abort} ) {
      say STDERR "Aborting query for $word: ", $words[$word]{word};
      for my $chunk ( keys %{ $words[$word]{processing} } ) {
	# skip finished searches
	next if exists $words[$word]{processing}{$chunk}{finished};

	# kill running corpus search
	my $core = $words[$word]{processing}{$chunk}{started};
	kill USR1 => $pid[$core];
	# Wait for EOF on the pipe
	my $return;
	until ( defined ( $return = $from_child[$core]->getline() )
		and $return eq "EOF\n" ) { };

	# update $idle_cores and $processing
	push @$idle_cores, $core;
	delete $processing->{$core};
      }
      # delete searches still on the queue
      shift @$queue
	while defined $queue->[0] and $queue->[0]{word} == $word;

      # set the removed flag for the unfinished word
      $words[$word]{removed} = 1;
      delete $words[$word]{abort};

      # gui postprocessing
      unmark_word($word);
      overstrike_word($word);
      my $total = @words;
      update_progress_bar(++$finished->{total}, $total, $ls{total});
      delete_word_progress_bar($word);
    }
  }

  # start new searches as requested
  while (@$idle_cores and @$queue) {
    my $core = shift @$idle_cores;

    my $item = shift @$queue;
    my $word  = $item->{word};
    my $chunk = $item->{chunk};
    my $type  = $item->{type};
    my @patterns    = @{ $item->{patterns} };
    my @author_nums = @{ $item->{authors} };

    if ($chunk == 1) {
      mark_word($word);
      make_word_progress_bar($word);
    }
    else {
      make_word_progress_info_chunk($word, $chunk);
    }
    # store some information for the progress info frame
    $words[$word]{processing}{$chunk}{started} = $core;
    $words[$word]{processing}{$chunk}{total} = @author_nums;

    # make process start
    my $ascii_word = $words[$word]{word};
    if ($ascii_word =~ m/[Α-ω]/) {
      $ascii_word = lc Diogenes::UnicodeInput->unicode_greek_to_beta($ascii_word);
      $ascii_word =~ tr#/\\|()=\*##d;
    }
    $to_child[$core]->say($word, '_', $ascii_word, '_', $chunk);
    $to_child[$core]->say($_) for @patterns;
    $to_child[$core]->say();
    $to_child[$core]->say($type);
    $to_child[$core]->say($_) for @author_nums;
    $to_child[$core]->say();
    $processing->{$core} = [ $word, $chunk ];
  }

  # check for updates and finished searches
  for my $core (0..$CORES) {
    my $input = $from_child[$core]->getline();
    if ( defined $input and $input ne "EOF\n" ) {
      my $word  = $processing->{$core}[0];
      my $chunk = $processing->{$core}[1];
      chomp($input);
      # currently processed author counter
      if ($input =~ /^A: (\d+) (\d+)$/) {
	$words[$word]{processing}{$chunk}{pass} = 0;
	$words[$word]{processing}{$chunk}{finished_files} = $1;
	$words[$word]{processing}{$chunk}{active_file} = $2;
	update_word_progress_bars($word)
      }
      # current pass
      elsif ($input =~ /^P: (\d+)$/) {
	$words[$word]{processing}{$chunk}{pass} = $1;
	update_word_progress_bars($word);
      }
      # finished searches
      elsif ($input =~ /\/\d+_\w+_(\d+)\.dat$/) {
	# load name into the finished hash
	$finished->{$word}{$1} = $input;
	# toggle finished flag (needed for the progress bars)
	$words[$word]{processing}{$chunk}{finished} = 1;

	# update queues
	push @$idle_cores, $core;
	delete $processing->{$core};
      }
      # error handling
      elsif ($input =~ /ERROR: (.*)$/) {
	error("Worker #$core: $ls{error_save} ",
	      "$processing->{$core}[0]_",
	      $words[$processing->{$core}[0]]{word},
	      ".dat: $1");
	push @$idle_cores, $core;
	delete $processing->{$core};
      }
      # die on undefined behaviour
      else {
	die "Malformed message from $core ($pid[$core])\n$input"
      }
    }
  }

  # if all searches of a word have finished, load the results
  for my $word (0..$#words) {
    if ( %{ $finished->{$word} } == $finished->{last} ) {
      say $finished->{total}++;

      # retrieve data
      for my $chunk (1..$finished->{last}) {
	my $filename = $finished->{$word}{$chunk};
	say "$filename does not yet exist!"
	  until -e $filename;
	my $data = retrieve $filename;

	warn $word, $words[$word]{word},
	  ", chunk $chunk: no result retrieved"
	  unless defined $data->{result};

	${ $words[$word]{result} } .= ${ $data->{result} };
	$words[$word]{hits}        += $data->{hits};
	@{ $words[$word]{seen_all} }{keys %{ $data->{seen_all} }} =
	  values %{ $data->{seen_all} };
	@{ $words[$word]{match_start_all} }{keys %{ $data->{match_start_all} }} =
	  values %{ $data->{match_start_all} };
	@{ $words[$word]{not_printed} }{keys %{ $data->{not_printed} }} =
	  values %{ $data->{not_printed} };
      }

      # GUI postprocessing
      unmark_word($word);
      my $total = @words;
      update_progress_bar($finished->{total}, $total, $ls{total});
      update_stats_tw($word);
      delete_word_progress_bar($word);

      $finished->{$word} = {}
    }
  }

  # if (@$queue or %$processing) {
  if ($finished->{total} < @words) {
    Tkx::after( 5, [\&manage_searches,
		    $queue, $processing, $finished, $idle_cores] );
  }
  else {
    Tkx::after( 5, \&end_search )
  }
}

sub abort_searches {
  my ($queue, $processing) = @_;

  for my $core (0..$CORES) {
    # Throw an exception in child process
    kill USR1 => $pid[$core];
    # Wait for EOF on the pipe
    my $return;
    until ( defined ( $return = $from_child[$core]->getline() )
	    and $return eq "EOF\n" ) { };
    # set the removed flag for the unfinished searches form words array
    my @aborted = map { $queue->[$_]{word} } 0 .. $#{ $queue };
    for my $core (0..$CORES) {
      push @aborted, $processing->{$core}[0]
	if defined $processing->{$core};
    }
    $words[$_]{removed} = 1 for @aborted;

    end_search();
  }
}

sub mark_word {
  say my $index = shift;

  # mark words currently searched for in $input_txt
  my @positions  = @{ $words[$index]{positions} };
  my $times_seen = $words[$index]{times_seen};
  while ($times_seen--) {
    my $line  = shift @positions;
    my $begin = shift @positions;
    my $end   = shift @positions;
    $input_txt->tag_add("searching", "$line.$begin", "$line.$end");
  }
}

sub unmark_word {
  my $index = shift;

  # unmark words currently searched for in $input_txt
  my @positions  = @{ $words[$index]{positions} };
  my $times_seen = $words[$index]{times_seen};
  while ($times_seen--) {
    my $line  = shift @positions;
    my $begin = shift @positions;
    my $end   = shift @positions;
    $input_txt->tag_remove("searching", "$line.$begin", "$line.$end");
  }
}

sub overstrike_word {
  say my $index = shift;

  # mark words currently searched for in $input_txt
  my @positions  = @{ $words[$index]{positions} };
  my $times_seen = $words[$index]{times_seen};
  while ($times_seen--) {
    my $line  = shift @positions;
    my $begin = shift @positions;
    my $end   = shift @positions;
    $input_txt->tag_add("aborted", "$line.$begin", "$line.$end");
  }
}

sub make_pattern_list {
  my $index = shift;

  my @patterns;
  if ($st_lemma) {
    @patterns = @{ $words[$index]{forms} };
      for my $pattern (@patterns) {
	# make pattern diacritics insensitive
	# already done in make_lemma_patterns!
	# $pattern  =~ tr#/\\=()|\*##d;
	# only whole words should be matched
	# also already done in make_lemma_patterns
	# $pattern = " $pattern ";
	say "#$pattern#";
      }
  }
  else {
    my $pattern = $words[$index]{word};
    # make all beta code
    $pattern = lc Diogenes::UnicodeInput->unicode_greek_to_beta($pattern)
      if $pattern =~ m/[Α-ω]/;
    # make pattern to diacritics insensitive
    $pattern  =~ tr#/\\=()|\*##d;
    # only whole words
    $pattern = " $pattern ";
    say "#$pattern#";
    push @patterns, $pattern;
  }
  return @patterns;
}

sub make_author_list {
  my @author_nums;
  for ($si_corpus) {
    if (/^TLG$/) {
      push @author_nums, "tlg", @{ $tlg_lister->{tlg_ordered_authnums} };
    }
    elsif (/PHI$/) {
      error($ls{error_implemented_PHI});
      end_search();
      edit_search();
      return undef;
    }
    # List of author numbers
    elsif (/^\d{1,4}(?:,\s*\d{1,4})*$/) {
      push @author_nums, "tlg";
      push @author_nums, $& while /\d{1,4}/g;
    }
    # error
    else {
      error($ls{error_unknown_st}, $_);
      end_search();
      edit_search();
      return undef;
    }
  }
  return @author_nums;
}

#------------------------------------------------
# STEP 4: CLEANUP

sub end_search {
  $interrupt = 0;
  $input_txt->tag_remove("searching", '1.0', 'end');

  clear_directory($path);

  $progress_w_cnt = 0;
  $progress_frm->g_destroy() if $progress_frm;
  $lemmata_frm->g_destroy() if $lemmata_frm;

  $input_bttn->configure
    (
     -text => $ls{edit},
     -command => \&edit_search,
    );
  $input_bttn_text = 'edit';
  $mw->g_bind("<Control-Return>", sub { $results_bttn->invoke() } );
  $searching = 0; update_menu();
  return 1;
}

sub edit_search {
  $input_bttn->configure
    (
     -text => $ls{search},
     -command => \&begin_search,
    );
  $input_bttn_text = 'search';
  $input_txt->tag_remove("blacklist", '1.0', 'end');
  $input_txt->tag_remove("aborted", '1.0', 'end');
  $input_txt->configure(-state => "normal");
  $input_txt->g_focus();
  $mw->g_bind("<Control-Return>", sub { $input_bttn->invoke() } );

  # reenable the switches
  $st_rbt_vbt->state('!disabled');
  $st_rbt_lem->state('!disabled');
  # $st_cbt_syn->state('!disabled');
  # $st_cbt_cnt->state('!disabled');

}

#------------------------------------------------
# PART 2: THE STATISTICS VIEW
#------------------------------------------------

# CALLBACKS IN THE STATISTICS VIEW
sub get_selection {
  @selected_str = split /\s+/, $stats_tw->selection();
  @selected_num = ();
  return unless @selected_str;

  for my $index (0..$#words) {
    for my $str (@selected_str) {
      push @selected_num, $index if $str eq "$words[$index]{word}.$index";
    }
  }
}

sub rm_selection{
  $stats_tw->selection('set', '');
  update_selection();
}

sub update_selection {
  get_selection();
  if (@selected_str and $stats_tw) {
    # Activate Buttons
    $stats_show_bttn->state('!disabled');
    $stats_add_bttn->state ('!disabled');
    $stats_edit_bttn->state ('!disabled');
    $stats_rm_bttn->state  ('!disabled');
    $stats_weight_sb->state('!disabled');

    # Load weight value of the last selected item into $weight
    $weight = ($#selected_str == 0)
      ? $stats_tw->set("$selected_str[0]", "weight")
      : '';
  }
  else {
    $stats_show_bttn->state('disabled');
    $stats_add_bttn->state ('disabled');
    $stats_edit_bttn->state ('disabled');
    $stats_rm_bttn->state  ('disabled');
    $stats_weight_sb->state('disabled');
    $weight = '';
  }
}

sub set_weight_selection {
  return if $weight eq '';
  for my $str (@selected_str) {
    $stats_tw->set ( "$str", weight => $weight );
  }
}

sub increment_weight_selection {
  for my $str (@selected_str) {
    my $weight = $stats_tw->set ( "$str", "weight");
    $weight++;
    $stats_tw->set ( "$str", weight => $weight );
  }
}

sub decrement_weight_selection {
  for my $str (@selected_str) {
    my $weight = $stats_tw->set ( "$str", "weight");
    $weight = ($weight > 0)
      ? --$weight
      : 0;
    $stats_tw->set ( "$str", weight => $weight );
  }
}

sub empty_weight {
  $weight = ''  if $#selected_str > 0
}

sub add_words {
  error($ls{error_implemented});
}

sub edit_words {
  error($ls{error_implemented});
}

sub rm_words {
  # TODO: Undo function

  # delete words from $stats_tw
  $stats_tw->delete("@selected_str");

  # set the removed flag
  for my $num (@selected_num) {
     $words[$num]{removed} = 1;
   }

 #  # delete words from $words
 #  my @indices = ();
 # INDEX: for my $index (0..$#words)  {
 #    for my $num (@selected_num) {
 #      next INDEX if $num == $index;
 #    }
 #    push @indices, $index;
 #  }
 #  @words = @words[@indices];

  @selected_num = ();
}

sub context_sb_callback {
  # no values less than 1 accepted
  return if $context eq '';
  $context = 1 if $context < 1;

  # # update context types strings according to plural and singular
  $context_type = get_context_type();
  @context_types_str = ($context > 1)
    ? @context_types_str_plur
    : @context_types_str_sing;
  $context_type_str = get_context_type_str();
  $stats_context_cbb->configure(-values => \@context_types_str)
}

# The final evaluation
sub begin_evaluation {
  $searching = 1; update_menu();
  # Get context values
  return unless $context;
  $context_type = get_context_type();
  error(get_context_type_str(), ": $ls{error_implemented}") and return
    if grep $context_type eq $_, qw(clause sentence line);

  # Get the entered weight for each word
  for my $i (0..$#words) {
    my $word = $words[$i]{word};
    $words[$i]{weight} = ( $words[$i]{removed} )
      ? 0
      : $stats_tw->set ( "$word.$i", "weight");
  }

  # Prepare $results_txt, delete old separators and delete data
  $textframes{$results_txt} = [];
  for my $tag ( split ' ', $results_txt->tag_names() ) {
    $results_txt->tag_delete("$tag") if
      $tag =~ /^[ts]\d+/;
  }
  delete $elided_passages{$results_txt};
  $results_txt->configure(-state => 'normal');
  $results_txt->delete('1.0', 'end');
  $results_n->tab('2', -state => 'normal');
  $results_n->select('2');

  # make progress bars
  my $total = @words;
  make_progress_bars($total, $ls{preparing});

  # Initialize the %results data structure
  %results = ();
  my @queue = 0..$#words;
  Tkx::after( 5, [\&populate_results, @queue]);
}

sub populate_results {
  my $w = shift;
  my $word  = $words[$w];
  my @queue = @_;
  my @tlg_numbers = keys %{ $word->{seen_all} };

  # make the blacklist
  my %deleted;
  for my $arrayref (@{ $deleted_passages{$w} }) {
    my $auth = shift @$arrayref;
    $auth = 'tlg' . $auth . '.txt';
    $deleted{$auth}{$_} = 1 for @$arrayref;
  }
  say "Blacklist";
  print Dumper %deleted;

  # get the single matches
  for my $tlg_number (@tlg_numbers) {
    next unless defined $word->{seen_all}{$tlg_number};
    my @match_starts = sort numerically @{ $word->{match_start_all}{$tlg_number} };
    my @matches      = sort numerically @{ $word->{seen_all}{$tlg_number} };

    # make for each hit a hash, pass the needed values from @words,
    # add the data for $match_start
    for my $i (0..$#matches) {
      # skip deleted matches
      next if exists $deleted{$tlg_number}{ $matches[$i] };
      # $results{$tlg_number}{$hit} = $word;
      $results{$tlg_number}{$matches[$i]}{word}   = $word->{word};
      $results{$tlg_number}{$matches[$i]}{hits}   = $word->{hits};
      $results{$tlg_number}{$matches[$i]}{result} = $word->{result};
      $results{$tlg_number}{$matches[$i]}{weight} = $word->{weight};
      $results{$tlg_number}{$matches[$i]}{match_start} = $match_starts[$i];
      # $results{$tlg_number}{$matches[$i]}{query}  = $word->{query};
    }
  }

  if (@queue) {
    # update progress bars
    my $total    = @words;
    my $finished = $total - @queue;
    update_progress_bar($finished, $total, $ls{preparing});

    Tkx::after( 5, [\&populate_results, @queue]);
  }
  else {
    $progress_frm->g_destroy() if $progress_frm;
    Tkx::after( 5, \&get_context_matches);
  }
}

sub get_context_matches {
  # get the matches in context
  for my $tlg_number (keys %results) {
    my @in_context = ();

    for my $match
      (sort numerically keys %{ $results{$tlg_number} })
      {
	if (@in_context) {
	  # old matches out of context leave @in_context
	  while (@in_context) {
	    last if $match < ($in_context[0] + $context);
	    shift @in_context;
	  }

	  # remove duplicate matches & matches for the current word
	  my %hash = ();
	  for my $pos (@in_context) {
	    $hash{ $results{$tlg_number}{$pos}{word} } = $pos;
	  }
	  delete $hash{ $results{$tlg_number}{$match}{word} };
	  @in_context = sort numerically values %hash;
	}

	# clear @in_context for the last matches in order to avoid
	# duplicate matches
	for my $last_hit (@in_context) {
	  $results{$tlg_number}{$last_hit}{in_context} = [];
	}

	$results{$tlg_number}{$match}{in_context} = [@in_context];
	push @in_context, $match;
      }
  }
  Tkx::after( 5, \&setup_output);
}

sub setup_output {
  %output = ();

  # make pattern list for the whole passage
  my @pattern_list;
  if ($st_lemma) {
    @pattern_list = map " $words[$_]{word} " , (0..$#words);
    for (0..$#words) {
      push @pattern_list, @{ $words[$_]{forms} };
    }
    # @pattern_list = map { " $_ " } @pattern_list
    # say @pattern_list = map { tr#/\\=()|\*##d ; " $_ " } @pattern_list;
  }
  else {
    @pattern_list = map {
      my $pattern = $words[$_]{word};
      # make all beta code
      $pattern = lc Diogenes::UnicodeInput->unicode_greek_to_beta($pattern)
	if $pattern =~ m/[Α-ω]/;
      # make pattern to diacritics insensitive
      $pattern  =~ tr#/\\=()|\*##d;
      " $pattern "
    } (0..$#words);
  }

  # TODO: Get a better configuration of the Diogenes::Search object
  my $printer = Diogenes::Search->new
    (
     -type => 'tlg',
     -pattern_list => [ @pattern_list ],
     # -max_context => 1000,
     -context => 'paragraph',
    );
  $printer->{current_lang} = 'g';

  # make progress bars
  my $total = keys %results;
  make_progress_bars($total, $ls{evaluating});

  # setup the queue, start the extraction of the passages
  my $queue = [ keys %results ];
  Tkx::after( 5, [\&extract_hits, $printer, $queue] );
}

sub extract_hits {
  my $printer    = shift;
  my $queue      = shift;
  my $tlg_number = shift @$queue;

  my $short_num = $tlg_number;
  $short_num =~ tr/0-9//cds;
  $printer->parse_idt($short_num);

  # open the desired file, load it into $buf;
  my ($buf, $inp);
  $printer->{buf} = \$buf;
  {
    local $/;
    undef $/;
    open $inp, "$printer->{cdrom_dir}$tlg_number"
      or die ("Couln't open $tlg_number!");
    binmode $inp;
  }
  $buf = <$inp>;

  my $i = 0;
 MATCH: for my $match (sort numerically keys %{ $results{$tlg_number} }) {
    my $word  = $results{$tlg_number}{$match}{word};
    my $start = $results{$tlg_number}{$match}{match_start};
    my @in_context = @{ $results{$tlg_number}{$match}{in_context} };

    # filter out results that do not reach the threshold
    my $match_weight = $results{$tlg_number}{$match}{weight};
    for (@in_context) {
      $match_weight += $results{$tlg_number}{$_}{weight}
    }
    next MATCH if $match_weight < $threshold;

    # get info for the other matches in the same context
    my (@matched_words, @start_pos, @end_pos) = ();
    for my $ct_match (@in_context) {
      push @matched_words, $results{$tlg_number}{$ct_match}{word};
      push @start_pos,     $results{$tlg_number}{$ct_match}{match_start};
      push @end_pos,       $ct_match;
    }
    push @matched_words, $results{$tlg_number}{$match}{word};
    push @start_pos,     $results{$tlg_number}{$match}{match_start};
    push @end_pos,       $match;

    # Manipulate the printer object
    $printer->{min_matches} = @matched_words;
    @{ $printer->{seen}{$tlg_number} }        = @end_pos;
    @{ $printer->{match_start}{$tlg_number} } = @start_pos;

    # Print output to string $out_str
    {
      my $out_str;
      local *STDOUT;
      open STDOUT, '>:raw', \$out_str;

      my $count = @end_pos;
      my $info = "$ls{list_st}: @matched_words\t($ls{total_weight}: $match_weight)";

      $printer->extract_hits($tlg_number, 1);

      # If the passage is already reported, Diogenes gives us nothing
      $out_str = $out_str || '';
      unless ($out_str) {
	# append @matched words to the last reported entry
	my @last_matched_words = @{ $output{$tlg_number}[$i-1]{matched_words} };
	push @last_matched_words, @matched_words;
	# delete double entries
	my %last_matched_words = map { $_, 1 } @last_matched_words;
	@{ $output{$tlg_number}[$i-1]{matched_words} } = keys %last_matched_words;
	next MATCH;
      }

      $output{$tlg_number}[$i]{output} = $out_str;
      $output{$tlg_number}[$i]{info}  = $info;
      $output{$tlg_number}[$i]{count}  = $count;
      $output{$tlg_number}[$i]{matched_words}  = \@matched_words;
      $output{$tlg_number}[$i]{start_pos}  = \@start_pos;
      $output{$tlg_number}[$i]{end_pos}  = \@end_pos;
    }
    # # DEBUGGING, seems ok
    # say for @{ $output{$tlg_number}[$i]{matched_words} };
    # say $output{$tlg_number}[$i]{info};
    # say "";
    # say $output{$tlg_number}[$i]{count};
    # say $output{$tlg_number}[$i]{output};
    # say "\n\n";
    $i++;
  }

  # update progress bars
  my $total    = keys %results;
  my $finished = $total - @$queue;
  update_progress_bar($finished, $total, $ls{evaluating});

  if (@$queue) {
    Tkx::after( 5, [\&extract_hits, $printer,$queue] );
  }
  else {
    Tkx::after( 5, [\&finish_output, $printer] );
  }
}

sub finish_output {
#  my $printer = shift;
  my $output_string = '';

  # sort and concatenate results
  # Get the keys of $results (that is, the tlg file names) into
  # chronological order
  my @ordered_nums = @{ $tlg_lister->{tlg_ordered_authnums} };
  my @ordered_result_keys = ();
  s/^.*$/tlg$&.txt/ for @ordered_nums;
  for (@ordered_nums) {
    push @ordered_result_keys, $_ if exists $results{$_} ;
  }

  my $sort_output = 'chronological';
  # my $sort_output = 'numerical';
  for ($sort_output) {
    if (/numerical/) {
      @ordered_result_keys = sort keys %output
    }
    if (/reverse/) {
      @ordered_result_keys = reverse @ordered_result_keys;
    }
  }

  my (@location, @info);
  for my $tlg_number (@ordered_result_keys) {
    for my $match (0..$#{ $output{$tlg_number} }) {
      $output_string .= $output{$tlg_number}[$match]{output};
      my $number = substr $tlg_number, 3, 4;
      my %hash = (author => $number,
		  match  => $output{$tlg_number}[$match]{end_pos}[0]);
      push @location, \%hash;
      push @info, $output{$tlg_number}[$match]{info};
    }
  }

  # delete progress bars
  $progress_frm->g_destroy() if $progress_frm;
  $searching = 0; update_menu();

  if ($output_string) {
    print_results( \$output_string, $results_txt, \@location, \@info );
  }
  else {
    $results_n->tab('2', -state => 'hidden');
    error($ls{error_results});
    $results_txt->configure(-state => 'disabled');
  }
}


sub print_results {
  my $output_string = shift;
  my $output_txt    = shift;
  my $location      = shift;
  my $info_or_menu  = shift;
  # viewer_txt has as 4th arg its menu, $results_txt a reference to the @info array
  my $info;
  my $output_m = {};
  # $results_txt
  if    (ref $info_or_menu eq 'ARRAY') {
    $info = $info_or_menu;
    $output_m->{menu} = $menu;
    $output_m->{passage} = $passage_m;
    $output_m->{export} = $export_m;

  }
  elsif (ref $info_or_menu eq 'Tkx::widget') {
    $output_m->{menu} = $info_or_menu;
    $output_m->{passage} = $output_m->{menu}->new_menu;
    $output_m->{export} = $output_m->{menu}->new_menu;
  }
  else {
    warn "$info_or_menu should be ARRAY or.Tkx::widget, but is",
      ref $info_or_menu, "!"
      and return;
  }
  $output_m->{menu}->insert
    (
     1, 'cascade',
     -menu      => $output_m->{passage},
     -label     => $ls{passage},
     -underline => 0,
    );
  $output_m->{menu}->insert
    (
     2,'cascade',
     -menu      => $output_m->{export},
     -label     => $ls{export},
     -underline => 0,
    );
  $output_m->{passage}->add_command # index 0
    (
     -label => "$ls{delete_selection} (DEL)",
     -underline => 0,
     -state => 'disabled'
    );
  $output_m->{passage}->add_command # index 1
    (
     -label => "$ls{undo} (y)",
     -underline => 0,
#     -state => 'disabled'
    );
  $output_m->{passage}->add_command # index 2
    (
     -label => "$ls{show_context} (RET)",
     -underline => 0,
     -state => 'disabled'
    );
  $output_m->{export}->add_command # index 0
    (
     -label => "$ls{export_to_txt} (T)",
     -underline => 0,
#     -state => 'disabled'
    );
  $output_m->{export}->add_command # index 1
    (
     -label => "$ls{export_to_mom} (M)",
     -underline => 0,
#     -state => 'disabled'
    );
  $output_m->{export}->add_command # index 2
    (
     -label => "$ls{export_to_pdf} (P)...",
     -underline => 0,
#     -state => 'disabled'
    );

  $printer_interrupt = 0;
  $output_txt->g_focus();
  # $output_txt->g_bindtags(['Text', '.t', 'all', "$output_txt"]);

  $textframes{$output_txt} = [];
  my $separator_width = ( $output_txt->g_winfo_width() - 20);
  my $textframe_count = 0;

  open my $str_fh, '<:utf8', $output_string;
  Tkx::after( 5, [\&print_results_chunk,
		  $str_fh, $output_txt, $location, $info,
		  $textframe_count, $output_m] );
}

sub print_results_chunk {
  my ($str_fh, $output_txt, $location, $info, $textframe_count, $output_m) = @_;
  my $separator_width = ( $output_txt->g_winfo_width() - 20);
  local $/ = '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~';
  $output_txt->configure(-state => 'normal');

  my $finished = 0;
  for (my $i = 0; $i < 20; $i++ ) {
    # get line index of the last printed line
    my $start = $output_txt->index('end');
    $start =~ s/(\d+).*/$1/;
    $start--;

    # get data or return
    my $str = <$str_fh>;
    if ($printer_interrupt or not $str) {
      # only here can we get the correct ranges for the separator
      # handler tag, so we have to correct it here!
      for (0..$textframe_count) {
	my $sepstart = $textframes{$output_txt}[$_]{separator_start} // next;
	$output_txt->tag_add("s$_", "$sepstart.0", "$sepstart.0 + 1l");
      }
      $finished = 1; last;
    }

    # create separator line unless the passage is the first reported
    if ($start > 1) {
      $textframes{$output_txt}[$textframe_count]{separator} =
	$output_txt->new_tk__canvas
	(-width => $separator_width, -height => 1, -bg => 'black');
      $output_txt->window_create
	("$start.0",
	 -window => $textframes{$output_txt}[$textframe_count]{separator});
      # the empty canvas with black bg makes for an excellent dividing line
      $textframes{$output_txt}[$textframe_count]{separator}->create_line
	(0,0,10000,0, -fill => 'black', -width => 3);
      $textframes{$output_txt}[$textframe_count]{separator_start} = $start;

      # handler tags
      $output_txt->tag_add("s$textframe_count", "$start.0", "$start.end");

      $textframe_count++;
    }

    # delete Diogenes' ASCII passage separator, including the \n
    chomp $str;
    # $str = substr($str, 0, -31)
    #   or next;

    # determine end of the header
    my $header_start = ($start > 1) ? $start + 1 : $start;
    my $header_end = index $str, "\n\n";

    # interpolate Lynkeus' info string
    my $info_start = 0;
    if ( ref $info and @$info
	 and  ($info_start = index $str, '###INFO###') != -1 ) {
      # insert the info into $str
      my $infoline = shift(@$info);
      $str = substr($str, 0, $info_start)
	. $infoline . substr($str, $info_start + 10);
      $header_end -= 10;
    }

    # replace --> and <-- with Tk's markings
    my (@highlight_starts, @highlight_ends);
    my $matchoffset = 0;
    while (0 <= $matchoffset < length($str)) {
      $matchoffset = index $str, '-->', $matchoffset;
      last if $matchoffset == -1;
      $str = substr($str, 0, $matchoffset) . substr($str, $matchoffset + 3);
      push @highlight_starts, $matchoffset;

      $matchoffset = index $str, '<--', $matchoffset;
      $str = substr($str, 0, $matchoffset) . substr($str, $matchoffset + 3);
      push @highlight_ends, $matchoffset;
    }

    # compute line numbers
    my $strlen = length $str;
    my $lineoffset = 0;
    my @linestarts = (0);
    while ($lineoffset < $strlen) {
      $lineoffset = index $str, "\n", $lineoffset;
      $lineoffset++;
      last unless $lineoffset;
      push @linestarts, $lineoffset;
    }

    # convert $header_end and $info_end into Tk's line.offset format
    my ($tk_info_start, $tk_info_end, $tk_header_end,
	@tk_highlight_starts, @tk_highlight_ends);
    my %highlights;
    my $multiline_start = 0;
    for my $i (1..$#linestarts) {
      my $linenum = $i - 1;
      my $linestart = $linestarts[$linenum];
      $linenum += $start;

      if (not $tk_header_end
	  and $linestarts[$i] > $header_end) {
	my $offset = $header_end - $linestart;
	$tk_header_end = "$linenum.$offset";
      }
      if ($info_start
	  and not $tk_info_start
	  and $linestarts[$i] > $info_start) {
	my $offset = $header_end - $linestart;
	my $nextline = $linenum + 1;
	$tk_info_start = "$linenum.$offset";
	$tk_info_end   = "$nextline.0";
      }

      my $starts = my $ends = 0;
      while (@highlight_starts and $linestarts[$i] > $highlight_starts[0]) {
	my $offset = shift(@highlight_starts) - $linestart;
	push @{ $highlights{$linenum}{start} }, $offset;
	$starts++;
      }
      while (@highlight_ends and $linestarts[$i] > $highlight_ends[0]) {
	my $offset = shift(@highlight_ends) - $linestart;
	push @{ $highlights{$linenum}{end} }, $offset;
	$ends++;
      }

      if    ( $starts == $ends ) { }
      elsif ( $starts > $ends  ) {
	$multiline_start = $linenum;
      }
      elsif ( $starts < $ends  ) {
	for my $line ( $multiline_start .. ($linenum - 1) ) {
	  my $nextline = $line + 1;
	  die $str
	    unless (defined $linestarts[$nextline - $start]
		    and defined $linestarts[$line - $start] );

	  my $linelen = 
	    $linestarts[$nextline - $start]
	    - $linestarts[$line - $start];
	  push @{ $highlights{$line}{end}    }, $linelen;
	  push @{ $highlights{$nextline}{start} }, 0;
	}
      }
    }

    # insert text
    $output_txt->insert("end", "$str");
    $output_txt->delete("end-1l", "end");
    # apply markup
    for my $linenum (sort numerically keys %highlights) {
      my $index = $#{ $highlights{$linenum}{start} };
      $index == $#{ $highlights{$linenum}{end} }
	or die "Unmatched hit markings in line $linenum";
      $output_txt->tag_add
	("matched",
	 "$linenum.$highlights{$linenum}{start}[$_]",
	 "$linenum.$highlights{$linenum}{end}[$_]"
	) for 0..$index;
    }
    $output_txt->tag_add("header", "$header_start.0", "$tk_header_end");
    $output_txt->tag_add("info", "$tk_info_start", "$tk_info_end")
      if $info_start;

    # retrieve and save location information this is buggy, because
    # the location data structure is not the same as the list of the
    # printed locations, because of the omission of
    # {already_reported}. The only possible fix for this is to alter
    # Diogenes that it makes a special array of all passages PRINTED
    # and use this information for our purposes! (DONE)
    $textframes{$output_txt}[$textframe_count]{location} = shift @$location;

    # elide the entry if it was elided in the past
    if ( exists $textframes{$output_txt}[0]{location}{word} ) {
      my $word = $textframes{$output_txt}[0]{location}{word};
      for (@{ $elided_passages{$output_txt}{$word}  }) {
	if ($_ == $textframe_count) {
	  $output_txt->tag_configure("t$textframe_count", -elide => 1);
	  $output_txt->tag_configure("s$textframe_count", -elide => 1);
	  last;
	}
      }
    }
    else {
      for (@{ $elided_passages{$output_txt}{0}  }) {
	if ($_ == $textframe_count) {
	  $output_txt->tag_configure("t$textframe_count", -elide => 1);
	  $output_txt->tag_configure("s$textframe_count", -elide => 1);
	  last;
	}
      }
    }

    # Textframe callback definitions
    my ($select, $unselect, $browse, $delete);
    {
      my $count = $textframe_count;

      $select = sub {
	my $bttn = shift;
	$textframe_mouse_pressed = $bttn if defined $bttn;
	my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	$output_txt->tag_add("sel", "$ranges[0]", "$ranges[1]");
	# $output_txt->tag_configure("t$$count", -background => 'green');
      };

      $unselect = sub {
	my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	$output_txt->tag_remove("sel", "$ranges[0]", "$ranges[1]")
	  unless $textframe_mouse_pressed;
      };

      $browse = sub {
	# Local version only when nothing is selected
	return if $output_txt->tag_ranges('sel');
	my $author = $textframes{$output_txt}[$count]{location}{author};
	my $offset = $textframes{$output_txt}[$count]{location}{match};
	invoke_browser($author, $offset);
      };

      $delete = sub {
	# Local version only when nothing is selected
	return if $output_txt->tag_ranges('sel');
	delete_passage($output_txt, $count);
      };
    }

    # add handler tags, activate callbacks
    $start = ($start == 1) ? 1 : $start + 1;
    $output_txt->tag_add("t$textframe_count", "$start.0", "end-1l");
    $output_txt->tag_bind("t$textframe_count", '<Double-ButtonRelease-1>', $select);
    $output_txt->tag_bind("t$textframe_count", '<Triple-ButtonRelease-1>', $browse);
    # $output_txt->tag_bind("t$textframe_count", '<Motion>', $select);
    # $output_txt->tag_bind("t$textframe_count", '<ButtonPress-1>', [$select, 1]);
    # $output_txt->tag_bind("t$textframe_count", '<ButtonRelease-1>', [$select, 0]);
    $output_txt->tag_bind("t$textframe_count", '<Return>', $browse);
    $output_txt->tag_bind("t$textframe_count", '<Delete>', $delete);
  }

  # Global callback definitions
  my ($move_forwards, $move_backwards, $browse, $delete, $undo);
  my ($export_txt, $export_roff, $export_pdf);
  # Helper function
  my $move_update_selection = sub {
    my ($output_txt, @ranges) = @_;
    $output_txt->tag_remove("sel", "1.0", "end");
    $output_txt->tag_add("sel", "$ranges[0]", "$ranges[1]");
    $output_txt->see("$ranges[1]");
    $output_txt->see("$ranges[0]");
  };

  $move_forwards = sub {
    my @selection = split ' ', $output_txt->tag_ranges('sel');
    if (@selection) {
      my $next_textframe;
      for my $count (0..$textframe_count) {
	if ( $output_txt->tag_nextrange("t$count", $selection[1]) ) {
	  # skip over elided passages
	  next if $output_txt->tag_cget("t$count", '-elide');
	  my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	  Tkx::after(1, [$move_update_selection, $output_txt, @ranges]);
	  return;
	}
      }
      # Lest the arrow keys clear the selection
      Tkx::after(1, [$move_update_selection, $output_txt, @selection]);
    }
    else {
      my ($start, undef) = split ' ', $output_txt->yview(), 2;
      my ($lastline, undef) = split ' ', $output_txt->index("end"), 2;
      my $firstline = int( $start * $lastline) + 1;
      $firstline++;
      for my $count (reverse 0..$textframe_count) {
	if ( $output_txt->tag_prevrange("t$count", "$firstline.0") ) {
	  # skip over elided passages
	  next if $output_txt->tag_cget("t$count", '-elide');
	  my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	  Tkx::after(1, [$move_update_selection, $output_txt, @ranges]);
	  return;
	}
      }
    }

  };

  $move_backwards = sub {
    my @selection = split ' ', $output_txt->tag_ranges('sel');
    if (@selection) {
      for my $count (reverse 0..$textframe_count) {
	if ( $output_txt->tag_prevrange("t$count", $selection[0]) ) {
	  # skip over elided passages
	  next if $output_txt->tag_cget("t$count", '-elide');
	  my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	  Tkx::after(1, [$move_update_selection, $output_txt, @ranges]);
	  return;
	}
      }
      # Lest the arrow keys clear the selection
      Tkx::after(1, [$move_update_selection, $output_txt, @selection]);
    }
    else {
      my ($start, undef) = split ' ', $output_txt->yview(), 2;
      my ($lastline, undef) = split ' ', $output_txt->index("end"), 2;
      my $firstline = int( $start * $lastline) + 1;
      $firstline++;
      for my $count (reverse 0..$textframe_count) {
	if ( $output_txt->tag_prevrange("t$count", "$firstline.0") ) {
	  # skip over elided passages
	  next if $output_txt->tag_cget("t$count", '-elide');
	  my @ranges = split /\s+/, $output_txt->tag_ranges("t$count");
	  Tkx::after(1, [$move_update_selection, $output_txt, @ranges]);
	  return;
	}
      }
    }
  };

  $browse = sub {
    my @selection = split ' ', $output_txt->tag_ranges('sel');
    return unless @selection;
    @selection = map { s/^(\d+).*/$1/r } @selection;
    for my $count (0..$textframe_count) {
      my @ranges = split ' ', $output_txt->tag_ranges("t$count");
      @ranges = map { s/^(\d+).*/$1/r } @ranges;
      if ( $ranges[0] <= $selection[0] <= $ranges[1] ) {
	my $author = $textframes{$output_txt}[$count]{location}{author};
	my $offset = $textframes{$output_txt}[$count]{location}{match};
	invoke_browser($author, $offset);
	last;
      }
    }
  };

  $delete = sub {
    my @selection = split ' ', $output_txt->tag_ranges('sel');
    return unless @selection;
    @selection = map { s/^(\d+).*/$1/r } @selection;
    for my $count (0..$textframe_count) {
      my @ranges = split ' ', $output_txt->tag_ranges("t$count");
      next unless @ranges;
      @ranges = map { s/^(\d+).*/$1/r } @ranges;
      if ( $ranges[0] <= $selection[0] <= $ranges[1] ) {
	delete_passage($output_txt, $count);
	if ( $ranges[0] <= $selection[1] <= $ranges[1] ) {
	  $move_forwards->() and return;
	}
	else {
	  $selection[0] = $ranges[1] + 2;
	}
      }
    }
  };

  # TODO make undo behave also locally in the actually openened textframe
  $undo = sub {
    my $word = ( exists $textframes{$output_txt}[0]{location}{word} )
      ? pop @{ $elided_passages{$output_txt}{history} }
      : 0;
    return unless defined $word;

    my $passage = pop @{ $elided_passages{$output_txt}{$word} };
    return unless defined $passage;

    $output_txt->tag_configure("t$passage", -elide => 0);
    $output_txt->tag_configure("s$passage", -elide => 0);
    print STDERR Dumper %elided_passages;
    # $results_txt: return
    return unless exists $textframes{$output_txt}[0]{location}{word};

    # $viewer text: undo the last edit of the blacklist.
    pop @{ $deleted_passages{$word} };
    my $blacklisted = @{ $deleted_passages{$word} };
    say "Word $word, $blacklisted";
    update_stats_tw_num($word, $blacklisted);

    print STDERR Dumper %deleted_passages;
  };

  $export_txt = sub {
    return unless my $filename = Tkx::tk___getSaveFile
    (
     -parent => $output_txt,
     -initialdir => '~',
     -defaultextension => '.txt',
     -filetypes => [
		    ['Plain Text', ['.txt']]
		   ],
    );
    my $output = export_to_text($output_txt);

    open my $fh, '>:utf8', $filename
      or die "Could not open $filename: $!";
    print { $fh } $output;
    close $fh;
  };

  $export_roff = sub {
    return unless my $filename = Tkx::tk___getSaveFile
    (
     -parent => $output_txt,
     -initialdir => '~',
     -defaultextension => '.mom',
     -filetypes => [
		    ['Roff Mom', ['.mom']]
		   ],
    );
    my $output = export_to_mom($output_txt);

    open my $fh, '>:utf8', $filename
      or die "Could not open $filename: $!";
    print { $fh } $output;
    close $fh;
  };

  $export_pdf = sub {
    return unless my $filename = Tkx::tk___getSaveFile
    (
     -parent => $output_txt,
     -initialdir => '~',
     -defaultextension => '.pdf',
     -filetypes => [ ['PDF', ['.pdf']] ],
    );
    my $output = export_to_mom($output_txt);
    Tkx::after(5, [\&groff, $output, $filename, $output_txt] );
  };
  $output_txt->g_bind('<y>', $undo);
  $output_txt->g_bind('<n>', $move_forwards);
  $output_txt->g_bind('<p>', $move_backwards);
  $output_txt->g_bind('<Up>',   $move_backwards);
  $output_txt->g_bind('<Down>', $move_forwards);
  $output_txt->g_bind('<Return>', $browse);
  $output_txt->g_bind('<Delete>', $delete);
  $output_txt->g_bind('<T>', $export_txt);
  $output_txt->g_bind('<M>', $export_roff);
  $output_txt->g_bind('<P>', $export_pdf) if $groff_available;
  $output_m->{passage}->entryconfigure(0, -command => $delete);
  $output_m->{passage}->entryconfigure(1, -command => $undo);
  $output_m->{passage}->entryconfigure(2, -command => $browse);
  $output_m->{export}->entryconfigure(0, -command => $export_txt);
  $output_m->{export}->entryconfigure(1, -command => $export_roff);
  if ($groff_available) {
    $output_m->{export}->entryconfigure(2, -command => $export_pdf)
  }
  else {
    $output_m->{export}->entryconfigure(2, -state => 'disabled')
  }

  my $selectionhandler = sub {
    if ( $output_txt->tag_ranges('sel') ) {
      $output_m->{passage}->entryconfigure($_, -state => 'normal') for 0, 2;
    }
    else {
      $output_m->{passage}->entryconfigure($_, -state => 'disabled') for 0, 2;
    }
  };
  $output_txt->g_bind('<<Selection>>', $selectionhandler);

  $output_txt->configure(-state => 'disabled');
  unless ($finished) {
    Tkx::after( 5, [\&print_results_chunk,
		    $str_fh, $output_txt, $location, $info,
		    $textframe_count, $output_m] );
  }
  else {
    close ($str_fh);
  }
}

sub delete_passage {
  my $output_txt = shift;
  my $count = shift;

  $output_txt->tag_configure("t$count", -elide => 1);
  $output_txt->tag_configure("s$count", -elide => 1);
  unless ( exists $textframes{$output_txt}[0]{location}{word} ) {
    # $results_txt
    push @{ $elided_passages{$output_txt}{0}  }, $count;
    return;
  }
  else {
    # $viewer_txt: push our passages to the blacklist stash
    my $word = $textframes{$output_txt}[$count]{location}{word};
    push @{ $elided_passages{$output_txt}{$word}   }, $count;
    push @{ $elided_passages{$output_txt}{history} }, $word;
    # history is needed for undoing the propper word in a
    # multiword $viewer_txt

    my $auth = $textframes{$output_txt}[$count]{location}{author};
    my @locations = ( $auth,
		      $textframes{$output_txt}[$count]{location}{match} );
    push @locations,
      @{ $textframes{$output_txt}[$count]{location}{not_printed} }
      if exists $textframes{$output_txt}[$count]{location}{not_printed};
    push @{ $deleted_passages{$word} }, \@locations;
    my $blacklisted = @{ $deleted_passages{$word} };
    update_stats_tw_num($word, $blacklisted);

    print STDERR Dumper %deleted_passages;
  }
}

sub update_separator_width {
  for my $txt (keys %textframes){
    Tkx::update();
    my $output_width = ( Tkx::winfo_width($txt) - 20);
    for my $item ( @{ $textframes{$txt} } ){
      $item->{separator}->configure(-width => $output_width)
	if $item->{separator};
    }
  }
}

sub update_stats_tw_num {
  my $index = shift;
  my $blacklisted = shift // 0;
  my $word = $words[$index]{word};
  my $hits = $words[$index]{hits} - $blacklisted;
  $stats_tw->set("$word.$index", hits => $hits);
}

#------------------------------------------------
# PART 3:  LEMMA SEARCH
#------------------------------------------------

# STEP 1: Setup the lemmata tab
sub setup_lemma_search {
  end_search() and return if $interrupt;

  %lemmata = ();
  make_lemmata_frm();
  Tkx::after( 10, [\&setup_lemma, -1] )
}

sub make_lemmata_frm {
  # Canvas container and scrollbar
  $lemmata_cvs = $results_tab0->new_tk__canvas();
  $lemmata_scroll = $results_tab0->new_ttk__scrollbar
    (
     -orient => 'vertical',
     -command => [$lemmata_cvs, 'yview']
    );
  $lemmata_cvs->configure(-yscrollcommand => [$lemmata_scroll, 'set']);
  $lemmata_scroll->g___autoscroll__autoscroll() if $autoscroll;

  $results_tab0->g_grid_columnconfigure(0, -weight => 1);
  $results_tab0->g_grid_rowconfigure(0, -weight => 1);
  $lemmata_cvs->g_grid(-column => 0, -row => 0, -sticky => "nwes");
  $lemmata_scroll->g_grid(-column => 1, -row => 0, -sticky => "nwes");

  # Actual frame
  $lemmata_frm = $lemmata_cvs->new_ttk__frame
    (
     -padding => "0 0 0 0",
    );

  # Necessary to make the frame both scrollable and expand to its maximal size
  $lemmata_frm->g_bind
    ('<Configure>', sub {
       $lemmata_cvs->configure(-scrollregion => $lemmata_cvs->bbox('all'));
     });
  $lemmata_cvs->g_bind
    ('<Configure>', sub {
       $lemmata_cvs->itemconfigure
	 ($lemmata_frm_handler,
	  -width => $lemmata_cvs->g_winfo_width(),
	 );
     });
  $lemmata_frm_handler = $lemmata_cvs->create_window
    (0, 0, -anchor => 'nw', -window => $lemmata_frm);

  # Geometry for the child widgets of frame
  $lemmata_frm->g_grid_columnconfigure(0, -weight => 1);
  $lemmata_frm->g_grid_columnconfigure(1, -weight => 30);
  $lemmata_frm->g_grid_columnconfigure(2, -weight => 10);

  $headword_l = $lemmata_frm->new_ttk__label
    (
     -text => ucfirst( $ls{form} ),
     -foreground => '#3E7804',
     -font => [-weight => 'bold']
    );
  $lemmata_l = $lemmata_frm->new_ttk__label
    (
     -text => ucfirst( $ls{lemma} ),
     -foreground => '#3E7804',
     -font => [-weight => 'bold']
    );
  $headword_l->g_grid(-column => 0, -row => 0, -sticky => 'new', -padx => '10 4', -pady => '0 10');
  $lemmata_l->g_grid (-column => 1, -row => 0, -sticky => 'new', -padx => '4 10', -pady => '0 10');
}

#------------------------------------------------
# STEP 2: Retrieve lemma data
sub setup_lemma {
  # TODO: Transliteration
  end_search() and return if $interrupt;
  my $i = shift;
  $i++;

  my $word = $words[$i]{word};

  # Get analyses, errormessage and next @word if analysis fails
  my %analyses = get_lemma($word);
  unless (keys %analyses) {
    error( $ls{error_lemma}, " $word!" );
    end_search();
    edit_search();
    return;
  }

  $words[$i]{analyses} = \%analyses;

  # Headword combobox
  my @headwords = sort keys %analyses;
  $headword_cbb[$i] = $lemmata_frm->new_ttk__combobox
    (
    # -textvariable => \$words[$i]{headword},
     -values => \@headwords,
     -state => 'readonly'
    );
  $words[$i]{headword} = $headwords[0];
  $headword_cbb[$i]->set( $words[$i]{headword} );
  $headword_cbb[$i]->g_bind
    ("<<ComboboxSelected>>",
     sub { headwords_callback($i) } );
  unless ($#headwords){   # disable the widget if there is no choice
    $headword_cbb[$i]->state('disabled');
  }

  # Lemmata combobox
  my @lemmata = sort keys %{ $analyses{$headwords[0]} };
  $lemmata_cbb[$i] = $lemmata_frm->new_ttk__combobox
    (
     -values => \@lemmata,
     -state => 'readonly'
    );
  $words[$i]{lemma} = $lemmata[0];
  $lemmata_cbb[$i]->set( $words[$i]{lemma} );
  $lemmata_cbb[$i]->g_bind
    ("<<ComboboxSelected>>",
     sub { $words[$i]{lemma} = $lemmata_cbb[$i]->get();
	   $lemmata_cbb[$i]->selection_clear
	 });
  unless ($#lemmata){		# disable the widget if there is no choice
    $lemmata_cbb[$i]->state('disabled');
  }

  # Show single forms button
  $lemmata_bttn[$i] = $lemmata_frm->new_ttk__button
    (
     -text => "$ls{single_forms}...",
     -command => sub { show_single_forms($i) },
     );

  # Geometry
  my $row = $i + 1;
  $headword_cbb[$i]->g_grid(-column => 0, -row => $row, -sticky => 'ew', -padx => '10 4', -pady => '0 5');
  $lemmata_cbb[$i] ->g_grid(-column => 1, -row => $row, -sticky => 'ew', -padx => '4 4', -pady => '0 5');
  $lemmata_bttn[$i]->g_grid(-column => 2, -row => $row, -sticky => 'ew', -padx => '4 10', -pady => '0 5');

  # say $words[$i]{headword};
  # say $words[$i]{lemma};
  # say $analyses{$words[$i]{headword}}{$words[$i]{lemma}}{number};

  if ($i == $#words) { Tkx::after( 10, [\&finish_setup_lemma, ($i+1) ] ); }
  else               { Tkx::after( 10, [\&setup_lemma, $i ]); }
}

sub headwords_callback {
  say my $i = shift;
  say my $headword = $words[$i]{headword} = $headword_cbb[$i]->get();
  say my @lemmata = sort keys %{ $words[$i]{analyses}{$headword} };

  my $lemma = $words[$i]{lemma} = $lemmata[0];
  $lemmata_cbb[$i]->set($lemma);
  $lemmata_cbb[$i]->configure
    (-values => \@lemmata);
  $headword_cbb[$i]->selection_clear;
  if ($#lemmata){
    $lemmata_cbb[$i]->state('!disabled')
  }
  else {
    $lemmata_cbb[$i]->state('disabled')
  }
}

sub show_single_forms {
  my $i = shift;
  my $word = $words[$i]{word};
  my $lemma = $words[$i]{lemma};
  my @forms = map { beta_to_utf8($_) } get_forms($i);

  $lemmata{$lemma}{undo_forms_blacklist} =
    $lemmata{$lemma}{forms_blacklist}
    if $lemmata{$lemma}{forms_blacklist};

  # New window
  $forms_win = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  my $window_title = "$ls{single_forms} $ls{for} $word";
  $forms_win->g_wm_title($window_title);
  $forms_win->g_wm_iconphoto('icon');

  # General window frame
  my $forms_frm = $forms_win->new_ttk__frame
    (-padding => "0 0 0 0");
  $forms_win->g_grid_columnconfigure(0, -weight => 1);
  $forms_win->g_grid_rowconfigure(0, -weight => 1);
  $forms_frm->g_grid(-column => 0, -row => 0, -sticky => "nwes");

  # Canvas holding contents frame, to make it scrollable
  my $forms_cvs = $forms_frm->new_tk__canvas
    (
     -width => 800,		# Hack
    );
  $forms_cvs->configure(-scrollregion => $forms_cvs->bbox('all'));
  my $forms_scroll = $forms_frm->new_ttk__scrollbar
    (
     -orient => 'vertical',
     -command => [$forms_cvs, 'yview']
    );
  $forms_cvs->configure(-yscrollcommand => [$forms_scroll, 'set']);
  $forms_scroll->g___autoscroll__autoscroll() if $autoscroll;

  # Geometry of the general window frame
  $forms_frm->g_grid_columnconfigure(0, -weight => 1);
  $forms_frm->g_grid_columnconfigure(1, -weight => 0);
  $forms_frm->g_grid_rowconfigure(0, -weight => 1);
  $forms_cvs->g_grid   (-column => 0, -row => 0, -sticky => "nwes");
  $forms_scroll->g_grid(-column => 1, -row => 0, -sticky => "ns");

  # Contents frame
  my $forms_content_frm = $forms_cvs->new_ttk__frame
    (-padding => "0 0 0 0");
  $forms_frm_handler = $forms_cvs->create_window
    (0, 0, -anchor => 'nw', -window => $forms_content_frm);
  $forms_cvs->configure( -scrollregion => $forms_cvs->bbox('all') );

  # Make the blacklist if it does not already exist
  unless ( $lemmata{$lemma}{forms_blacklist} ) {
    $lemmata{$lemma}{forms_blacklist}[$_] = 0 for 0..$#forms;
  }

  # Make the checkbuttons and link them to the checkbutton variable
  my @cbts;
  my $column = 0;
  my $max_column = 0;
  my $row = 0;
  for my $index (0..$#forms) {
    $cbts[$index] = $forms_content_frm->new_ttk__checkbutton
      (
       -text => $forms[$index], 
       -variable => \$lemmata{$lemma}{forms_blacklist}[$index],
       -onvalue => 0,
       -offvalue => 1,
      );
    $cbts[$index]->g_grid
      (-column => $column, -row => $row,-sticky => "ew",
       -padx => '4 4', -pady => '2 2');

    $column++;
    $max_column++ unless $max_column == 6;
    if ($column > 6) {
      $column = 0;
      $row++
    }
  }

  # Geometry for the child widgets of the forms content frame
  $forms_content_frm->g_grid_columnconfigure($_, -weight => 1) for 0..$max_column;
  $forms_content_frm->g_grid_rowconfigure($_, -weight => 1) for 0..$row;


  # button frame and buttons
  my $forms_bttn_frm = $forms_frm->new_ttk__frame
    ( -padding => "0 20 0 0");
  $forms_bttn_frm->g_grid
    (-column => 0, -row => 1, -columnspan => 2,
     -sticky => "ew", -padx => '4 4', -pady => '2 2');

  my $forms_select_all = $forms_bttn_frm->new_ttk__button
    (-text => $ls{select_all},
     -command => sub {
       $_ = 0 for @{ $lemmata{$lemma}{forms_blacklist} }
     },
    );
  my $forms_select_none = $forms_bttn_frm->new_ttk__button
    (-text => $ls{select_none},
     -command => sub {
       $_ = 1 for @{ $lemmata{$lemma}{forms_blacklist} }
       },
    );
  my $forms_cancel_bttn = $forms_bttn_frm->new_ttk__button
    (-text => $ls{cancel},
     -command => sub {
       if ($lemmata{$lemma}{undo_forms_blacklist}) {
	 $lemmata{$lemma}{forms_blacklist} = $lemmata{$lemma}{undo_forms_blacklist};
	 delete $lemmata{$lemma}{undo_forms_blacklist}
       }
       else { delete $lemmata{$lemma}{forms_blacklist} }
       $forms_win->g_destroy();
     },
    );
  my $forms_ok_bttn = $forms_bttn_frm->new_ttk__button
    (-text => $ls{ok},
     -command => sub {
       if ($lemmata{$lemma}{undo_forms_blacklist}) {
	 delete $lemmata{$lemma}{undo_forms_blacklist}
       }
       $forms_win->g_destroy();
     },
    );

  # Geometry for the child widgets of the forms button frame
  $forms_bttn_frm->g_grid_columnconfigure(0, -weight => 1);
  $forms_bttn_frm->g_grid_columnconfigure(1, -weight => 1);
  $forms_bttn_frm->g_grid_columnconfigure(2, -weight => 1);
  $forms_bttn_frm->g_grid_columnconfigure(3, -weight => 1);
  $forms_bttn_frm->g_grid_rowconfigure(1, -weight => 1);
  $forms_select_all->g_grid (-column => 0, -row => 0,-sticky => "ew", -padx => '4 4', -pady => '2 2');
  $forms_select_none->g_grid(-column => 1, -row => 0,-sticky => "ew", -padx => '4 4', -pady => '2 2');
  $forms_cancel_bttn->g_grid(-column => 2, -row => 0,-sticky => "ew", -padx => '4 4', -pady => '2 2');
  $forms_ok_bttn->g_grid    (-column => 3, -row => 0,-sticky => "ew", -padx => '4 4', -pady => '2 2');

  # Necessary to make the frame both scrollable and expand to its maximal size
  $forms_content_frm->g_bind
    ('<Configure>', sub {
       $forms_cvs->configure(-scrollregion => $forms_cvs->bbox('all'));
     });
  $forms_win->g_bind
    ('<Configure>', sub {
       $forms_cvs->itemconfigure
	 ($forms_frm_handler,
	  -width => $forms_cvs->g_winfo_width(),
	 );
     });
}

sub get_lemma {
  my $input_word = shift;

  # translate to betacode, if input if utf8 greek
  if ($input_word =~ m/[Α-ω]/) {
    $input_word = lc Diogenes::UnicodeInput->unicode_greek_to_beta($input_word);
  }

  my $strict = 0;
  if ($input_word =~ m![\/=()]!) {
    $strict = 1;
  }

  # get the indices of greek_analyses.tx
  load_greek_analyses_index();

  # open greek-analyses.txt, get the matches
  open my $analyses_fh, '<:raw',
    File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.txt')
    or die "Unable to load analyses file: $!\n";

  my @analyses_lines = ();
  my @alphabet = split //, 'abcdefghiklmnopqrstuwxyz';
  say my $letter = substr $input_word, 0, 1;
  say my $next_letter = do {
    my $index;
    for (0..$#alphabet){
      $index = $_ and last if $alphabet[$_] eq $letter;
    }
    $alphabet[++$index] || 'EOF';    
  };

  # Seek the miscellanea at the beginning
  seek $analyses_fh, 0, 0;
  my $switch = 0;
  while (<$analyses_fh>) {
    if (tell($analyses_fh) > $greek_analyses_indices{a} and not $switch) {
      seek $analyses_fh, $greek_analyses_indices{$letter}, 0;
      $switch++;
    }
    last if tell($analyses_fh) > $greek_analyses_indices{$next_letter};

    my $line = $_;
    /^(\S+)/;
    my $headword = $1;
    if ($headword) {
      $headword =~ tr#/\\=()|\*##d unless $strict;
      push @analyses_lines, $line if $headword eq $input_word;
    }
  }
  close $analyses_fh;

  say for @analyses_lines;

  # retrieve single matches
  my %analyses;
  for (@analyses_lines) {
    m/^(\S+)/;
    my $headword = $1;
    say $headword = beta_to_utf8($headword);

    while (m/{(.*?)}/g) {
      my $analysis = $1;
      my ($number, $lemma, $translation, $morphology, $dialects);

      if ($analysis =~ s/^(\S+)\s+\S+\s+//) { $number = $1 }
      if ($analysis =~ s/^(\S+)\t//)        { $lemma = $1 }
      if ($analysis =~ s/([^\t]+?)\t//)     { $translation = $1 }

      # transform lemma form beta code to utf8 greek
      $lemma =~ s/,(\S)/, $1/g;
      say $lemma = beta_to_utf8($lemma);

      my %hash;
      $hash{number} = $number;
      $hash{lemma} = $lemma;
      $hash{translation} = $translation;
      $hash{analysis} = $analysis;
      $hash{headword} = $headword;

      my $key = $hash{lemma} . " (" . $hash{translation} . ")";
      $analyses{$headword}{$key} = \%hash;
    }
  }

  return %analyses;
}

sub finish_setup_lemma {
  my $row = shift;
  $row++;

  #add continue button
  $lemmata_continue_bttn = $lemmata_frm->new_ttk__button
    (
     -text => $ls{continue},
     -command => \&setup_forms,
     -default => 'active',
    );
   $lemmata_continue_bttn->g_grid(-column => 0, -row => $row, -sticky => 'ew', -padx => '10 4', -pady => '10 5');

  # change input button to call $edit_search
    $input_bttn->configure
    (
     -text => $ls{edit},
     -command => \&edit_search,
    );
    $input_bttn_text = 'edit';
}

#------------------------------------------------
# STEP 3: Get the forms of the selected lemma
sub setup_forms {
  # configure input button
  $input_bttn->configure
    (
     -text => $ls{cancel},
     -command => sub { $interrupt = 1 },
    );
  $input_bttn_text = 'cancel';

  # Check for duplicates, merge positions
  my %seen;
  my @indices;
  for my $i (0..$#words) {
    my $headword = $words[$i]{headword};
    my $lemma    = $words[$i]{lemma};
    my $lemma_nr
      = $words[$i]{lemma_number}
      = $words[$i]{analyses}{$headword}{$lemma}{number};

    if ( defined $seen{$lemma_nr} ) {
      my $first = $seen{$lemma_nr};
      push @{ $words[$first]{positions} },
	@{ $words[$i]{positions} };
      $words[$first]{times_seen}++;
    }
    else {
      push @indices, $i;
      $seen{$lemma_nr} = $i;
    }
  }

  # remove duplicates
  @words = @words[@indices];

  Tkx::after( 10, [\&retrieve_forms, 0] );
}

sub retrieve_forms {
  my $i = shift;
  Tkx::after( 10, \&finish_lemma_setup ) and return if $i > $#words;

  # get the forms, remove the forms found on the word's forms_blacklist
  my $lemma = $words[$i]{lemma};
  my @forms = get_forms($i);
  my @indices =
    grep {
      ! $lemmata{$lemma}{forms_blacklist}[$_]
    } 0..$#forms;
  @forms = @forms[@indices];

  # transform the plain patterns into optimized regular expressions
  # the three variables controlling this process are the three globals
  # $min_stem, $max_alt and $chop_optional_groups
  @forms = make_lemma_patterns (\@forms);

  $words[$i]{forms} = \@forms;
  Tkx::after( 10, [\&retrieve_forms, ++$i] );
}

sub get_forms {
  my $i = shift;

  my $headword = $words[$i]{headword};
  my $lemma    = $words[$i]{lemma};
  my $number   = $words[$i]{analyses}{$headword}{$lemma}{number};
  die "I is $i" unless defined $number;

  # my $headword = $words[$i]{headword};
  # my $lemma    = $words[$i]{lemma};
  # my $number   = $words[$i]{lemma_number};

  open my $lemmata_fh, '<:raw',
    File::Spec->catfile($Bin, '..', 'data', 'greek-lemmata.txt')
    or die "Unable to load lemmata file: $!\n";

  my @forms = ();
  while (<$lemmata_fh>) {
    /^\S+\s+(\S+)/;
    my $lemma_number = $1;
    if ($lemma_number == $number) {
      my $line = $_;
      $line =~ s/^\S+\s+\S+//;

      while ($line =~ s/^\t(\S+)\s+([^\t]*)//g) {
	my $form = $1;
	my $analysis = $2;
	push @forms, $form;
      }
    }
  }
  close $lemmata_fh;

  return @forms;
}

#------------------------------------------------
# STEP 4: Make the plain patterns into optimized regular expressions

sub make_lemma_patterns {
  my $ref = shift;
  my $stem_min             = shift // $g_stem_min;
  my $max_alt              = shift // $g_max_alt;
  my $chop_optional_groups = shift // $g_chop_optional_groups;

  my @forms = @$ref;
  tr#/\\=()|\*##d for @forms; 	# no accents
  tr#'#I# for @forms;		# make ' safe; will be undone in the end!

  @forms = sort { length($b) <=> length($a) } @forms;
  $stem_min = (length[$#forms] < $stem_min)
    ? length[$#forms]
    : $stem_min;

  my $depth = length( $forms[0] ) - 1;
  my %patterns;
  my %paths;

  # make up the hash
  # stem
  for my $form (@forms) {
    my $stem = substr($form, 0, $stem_min);
    if ( length($form)  > $stem_min ) {
      $patterns{$stem} = {}
    }
    else {
      $patterns{$stem}{0} = $form
    }
  }

  # rest
  for my $level ($stem_min..$depth) {
    for my $form (@forms) {
      if ( length($form) > $level ) {
	my $letter = substr($form, $level, 1);

	my $command = '$patterns';
	my $stem = substr($form, 0, $stem_min);
	$command .= '{' . $stem . '}';
	for ($stem_min..$level) {
	  my $key = substr($form, $_, 1);
	  $command .= '{' . $key . '}';
	}
 	if ( length($form) - 1 > $level ) {
	  $command .= ' = {}';
	}
	else {
	  $command .= '{0} = $form;';
	}
	eval $command;
      }
    }
  }

  # tidy up
  sub tidy_up {
    my $hashref = shift;
    my $retval = 0;

    for my $key (keys %{ $hashref }) {
      next if $key eq '0';
      my @subkeys = keys %{ $hashref->{$key} };

      if (@subkeys == 1) {
	if ($subkeys[0] eq '0') {} # hitting the end of the road
	else {
	  $retval++;
	  my $subkey = $subkeys[0];
	  my $combined = $key . $subkey;
	  $hashref->{$combined} = $hashref->{$key}{$subkey};
	  delete $hashref->{$key};
	  $retval += tidy_up(\%{ $hashref->{$combined} });
	}
      }
      else {
	$retval = tidy_up(\%{ $hashref->{$key} });
      }
    }
    return $retval;
  }
  while ( tidy_up(\%patterns) ) {};

  # unroll the hash, make the patterns
  sub hash_to_pattern {
    my $hashref = shift;
    my $chop_optional_groups = shift;
    my %hash = %{ $hashref };
    my @keys = keys %hash;
    my $optional = 0;
    my @subpatterns;

    return '' if (@keys == 1 and $keys[0] eq '0');

    for my $key (@keys){
      if ($key eq '0') { $optional = 1 }
      else {
	my $subpattern =
	  hash_to_pattern(\%{ $hash{$key}  }, $chop_optional_groups);
	push @subpatterns, "$key$subpattern";
      }
    }
    my $pattern = join '|', @subpatterns;
    # we can skip the parens if
    # - there is only one subpattern
    # - and the whole group is not optional
    return $pattern if (not $#subpatterns and not $optional);

    # no parens around a single letter needed!
    $pattern = (length($pattern) > 1)
      ? "($pattern)"
      : $pattern;
    if ($optional) {
      $pattern = ($chop_optional_groups)
	? ''
	: "$pattern?";
    }
    # $pattern = "$pattern?" if $optional;
    return $pattern;
  }

  # undo over-optimization
  # helper function
  sub split_regex {
    my $subre = shift;
    my $parens_count = 0;
    my $strlength = length($subre);
    my @pos;
    for (my $i = 0; $i < $strlength; $i++) {
      if ( substr($subre, $i, 1) eq '(' ) { $parens_count++ }
      if ( substr($subre, $i, 1) eq ')' ) { $parens_count-- }
      if ( substr($subre, $i, 1) eq '|'
	   and $parens_count == 0 ) {
	push @pos, $i;
      }
    }
    push @pos, $strlength;

    my @split;
    for my $i (0..$#pos) {
      my $pos = $pos[$i];
      my $lastpos = ($i == 0) ? 0 : $pos[$i-1] + 1;
      my $length = $pos - $lastpos;
      my $split = ($pos == $strlength)
	? substr ($subre, $lastpos)
	: substr ($subre, $lastpos, $length);
      push @split, $split;
    }
    return @split;
  }

  sub decompose_regex {
    my $pattern = shift;
    my $max_alt = shift; 
    my $alterations = $pattern =~ tr/\|//;
    my @patterns;

    if ($alterations > $max_alt) {
      if ( $pattern =~ m#^([^()]+)\((.*)\)$# ) {
	my $stem = $1;
	my @rest = split_regex($2);
	@patterns = map { "$stem$_" } @rest;
      }
      elsif ( $pattern =~ m#^([^()]+)\((.*)\)\?$# ) { # group is optional
	my $stem = $1;
	my @rest = split_regex($2);
	@patterns = map { "$stem$_" } @rest;
	push @patterns, $stem;
      }
      else {die "Malformed pattern #pattern!"}

      @patterns = map { decompose_regex($_, $max_alt) } @patterns;
    }
    else { push @patterns, $pattern }
    return @patterns;
  }

  my @pattern_list;
  for my $key (keys %patterns) {
    my $pattern = $key;
    my %subhash = %{ $patterns{$key} };
    $pattern .= hash_to_pattern(\%subhash);
    my @patterns = decompose_regex($pattern, $max_alt);
    push @pattern_list, @patterns;
  }

  @pattern_list = map { tr/I/'/; $_ } @pattern_list; # reinsert '
  @pattern_list = ($chop_optional_groups)
    ? map { "$_ " } @pattern_list  # search term only at beginning of a word
    : map { " $_ " } @pattern_list; # only whole word searches
  say for @pattern_list;
  return @pattern_list;
}

#------------------------------------------------
# STEP 5: Finish the setup

sub finish_lemma_setup {
  $lemmata_cvs->g_destroy() and undef $lemmata_cvs;
  # $_->g_destroy() for @lemmata_cbb;
  # $_->g_destroy() for @headword_cbb;
  $results_n->tab('0', -state => 'hidden');
  $results_n->tab('1', -state => 'normal');
  $results_n->select('1');
  Tkx::after( 10, \&finish_setup );
}


#------------------------------------------------
# PART 4: SUBWINDOWING FUNCTIONS
#------------------------------------------------
# PREFERENCES
#------------------------------------------------
sub edit_configuration {
  my $arg = shift;		# simple switch
  my $cfg = ( $arg )
    ? Tkx::widget->new ( '.', -padx => 5, -pady => 5 )
    : $mw->new_toplevel(      -padx => 5, -pady => 5 );

  $cfg->g_wm_title('Lynkeus Configuration');
  if ($arg) {
    my $icon_path = File::Spec->catdir($Bin, '..', 'data', 'icon.png');
    Tkx::image_create_photo( "icon", -file => $icon_path);

    $ls{path_tlg} = "Path to TLG data";
    $ls{path_phi} = "Path to PHI data";
    $ls{path_ddp} = "Path to DDP data";
    $ls{browse}   = "Browse";
    $ls{defaults}    = "Default setrings";
    $ls{browsercols} = "Browser columns";

    $ls{search_type} = 'Search type';
    $ls{verbatim}    = 'verbatim';
    $ls{lemma}       = 'lemma';
    $ls{synonyma}    = 'verba synonyma';
    $ls{continentia} = 'verba continentia';
    $ls{search_in}   = 'Search in';

    $ls{threshold} = 'Threshold';
    $ls{lang}      = 'Language';

    $ls{cancel}         = 'Cancel';
    $ls{apply}          = 'Apply';
    $ls{ok}             = 'Ok';
  }
  $cfg->g_wm_iconphoto('icon');

  # Paths to the corpora
  my $cfg_path = $cfg->new_ttk__frame();
  my $tlgpath = ( exists $ENV{TLG_DIR} ) ? $ENV{TLG_DIR} : '';
  my $phipath = ( exists $ENV{PHI_DIR} ) ? $ENV{PHI_DIR} : '';
  my $ddppath = ( exists $ENV{DDP_DIR} ) ? $ENV{DDP_DIR} : '';
  my $findpath = sub {
    my $corpus = shift;
    my $pathref = shift;
    my $initialdir = (-d $$pathref) ? $$pathref : '';
    my $path = Tkx::tk___chooseDirectory
      (-initialdir => $initialdir,
       -parent => $cfg,
      );
    $$pathref = $path if $path;
  };
  my $tlgpath_l = $cfg_path->new_ttk__label(-text => "$ls{path_tlg}:");
  my $tlgpath_e = $cfg_path->new_ttk__entry(-textvariable => \$tlgpath, -state => 'normal');
  my $tlgpath_b = $cfg_path->new_ttk__button
    (-text => "$ls{browse}...", -command => [$findpath, 'tlg', \$tlgpath]);
  my $phipath_l = $cfg_path->new_ttk__label(-text => "$ls{path_phi}:");
  my $phipath_e = $cfg_path->new_ttk__entry(-textvariable => \$phipath);
  my $phipath_b = $cfg_path->new_ttk__button
    (-text => "$ls{browse}...", -command => [$findpath, 'phi', \$phipath]);
  my $ddppath_l = $cfg_path->new_ttk__label(-text => "$ls{path_ddp}:");
  my $ddppath_e = $cfg_path->new_ttk__entry(-textvariable => \$ddppath);
  my $ddppath_b = $cfg_path->new_ttk__button
    (-text => "$ls{browse}...", -command => [$findpath, 'ddp', \$ddppath]);

  # Default search mode
  my $cfg_settings = $cfg->new_ttk__labelframe(-text => $ls{defaults});
  my $search_var = ($arg or not $select_st_lemma) ? 'verbatim' : 'lemma';
  my $search_l = $cfg_settings->new_ttk__label(-text => "$ls{search_type}:");
  my $search_cbb = $cfg_settings->new_ttk__combobox
  (
   -textvariable => \$search_var,
   -values => [ 'verbatim', 'lemma' ],
  );
  $search_cbb->state('readonly');
  $search_cbb->g_bind("<<ComboboxSelected>>", sub { $search_cbb->selection_clear });

  my $synonyma = ($arg or not $select_st_synonyma) ? 0 : 1;
  my $synonyma_cbtn = $cfg_settings->new_ttk__checkbutton
    (-text => $ls{synonyma},
     -variable => \$synonyma,
     -onvalue => 1, -offvalue => 0);
  my $continentia = ($arg or not $select_st_continentia) ? 0 : 1;
  my $continentia_cbtn = $cfg_settings->new_ttk__checkbutton
    (-text => $ls{continentia},
     -variable => \$continentia,
     -onvalue => 1, -offvalue => 0);
  $synonyma_cbtn->state   ('disabled');
  $continentia_cbtn->state('disabled');

  # Default search  corpus
  my $corpus_var = 'TLG';
  my $corpus_l = $cfg_settings->new_ttk__label(-text => "$ls{search_in}:");
  my $corpus_cbb = $cfg_settings->new_ttk__combobox
  (
   -textvariable => \$corpus_var,
   -values => [ 'TLG' ],
  );
  $corpus_cbb->state('readonly');
  $corpus_cbb->g_bind("<<ComboboxSelected>>", sub { $corpus_cbb->selection_clear });

  # Default threshold
  my $thresh  = ($arg) ? 30 : $default_threshold_percent;
  my $threshold_l  = $cfg_settings->new_ttk__label(-text => "$ls{threshold} (%):");
  my $threshold_sb = $cfg_settings->new_ttk__spinbox
  (
   -from => 1.0,
   -to   => 100.0,
   -textvariable => \$thresh,
   -state => 'normal',
   -width => 4,
   -validate => 'all',
   -validatecommand => [ \&is_numeric, Tkx::Ev('%P')]
  );

  # GUI Language
  if ($arg) { my %languages = find_languages() }
  my %lang = reverse %languages;
  my $selected_language = $languages{$gui_lang};
  my $lang_l = $cfg_settings->new_ttk__label(-text => "$ls{lang}:");
  my $lang_cbb = $cfg_settings->new_ttk__combobox
  (
   -textvariable => \$selected_language,
   -values => [ keys %lang ],
  );
  $lang_cbb->state('readonly');
  $lang_cbb->g_bind("<<ComboboxSelected>>", sub { $lang_cbb->selection_clear });

  # Browser columns
  my $browsercolumns = ($arg) ? 2 : $browser_column_count + 1;
  my $browsercolumns_l  = $cfg_settings->new_ttk__label(-text => "$ls{browsercols}:");
  my $browsercolumns_sb = $cfg_settings->new_ttk__spinbox
  (
   -from => 1,
   -to   => 100,
   -textvariable => \$browsercolumns,
   -state => 'normal',
   -width => 4,
   -validate => 'all',
   -validatecommand => [ \&is_integer, Tkx::Ev('%P')]
  );

  # Buttons
  my $cfg_buttons = $cfg->new_ttk__frame();
  my $cancel_cfg = sub {
    $cfg->g_destroy();
  };
  my $apply_cfg = sub {
    Tkx::after( 5, [\&error, $cfg,  "No valid path to the TLG data specified!"] )
      and return
      unless -e File::Spec->catfile($tlgpath, "authtab.dir");
    my $searchtype = "$search_var";
    $searchtype .= "+synonyma"    if $synonyma;
    $searchtype .= "+continentia" if $continentia;
    $searchtype = '' if $searchtype eq 'verbatim';
    my $corpus = $corpus_var;
    $corpus = '' if $corpus eq 'TLG';
    my $lang = $lang{$selected_language};
    $lang = '' if $lang eq 'en';
    $thresh = '' if $thresh == 30;;
    $browsercolumns = '' if $browsercolumns == 2;

    make_config_dir() unless -d $config_dir;
    open my $config_fh, '>:utf8', $config_file
      or die "Cannot open config file $config_file: $!";
    say { $config_fh } 'tlg_dir "', $tlgpath, '"';
    say { $config_fh } 'phi_dir "', $phipath, '"' if $phipath;
    say { $config_fh } 'ddp_dir "', $ddppath, '"' if $ddppath;
    say { $config_fh } "language $lang" if $lang;
    say { $config_fh } "search_type $searchtype" if $searchtype;
    say { $config_fh } "corpus $corpus" if $corpus;
    say { $config_fh } "corpus $corpus" if $corpus;
    say { $config_fh } "threshold $thresh" if $thresh;
    say { $config_fh } "browser_columns $browsercolumns" if $browsercolumns;;
    $cfg->g_destroy();
    if ($arg) {			# Restart Lynkeus
      exec "perl", File::Spec->catfile($Bin, $0);
    }
    else {
      $select_st_lemma       = ($searchtype =~ /lemma/)       ? 1 : 0;
      $select_st_synonyma    = ($searchtype =~ /synonyma/)    ? 1 : 0;
      $select_st_continentia = ($searchtype =~ /continentia/) ? 1 : 0;
      $select_si_corpus          = $corpus         if $corpus;
      $gui_lang                  = $lang           if $lang;
      $default_threshold_percent = $thresh         if $thresh;
      $browser_column_count    = --$browsercolumns if $browsercolumns;
    }
  };
  my $cfg_cancel_bttn = $cfg_buttons->new_ttk__button
    (-text => $ls{cancel},
     -command => $cancel_cfg
    );
  my $cfg_bttn = $cfg_buttons->new_ttk__button
    (-text => $ls{apply},
     -command => $apply_cfg
    );

  # GRID: Windows
  $cfg->g_grid_columnconfigure(0, -weight => 1);
  $cfg->g_grid_rowconfigure   (0, -weight => 1);
  $cfg->g_grid_rowconfigure   (1, -weight => 1);
  $cfg->g_grid_rowconfigure   (2, -weight => 1);
  $cfg_path->g_grid    (-column => 0, -row => 0, -padx => '5 5', -pady => '5 5', -sticky => "nwes");
  $cfg_settings->g_grid(-column => 0, -row => 1, -padx => '5 5', -pady => '5 5', -sticky => "nwes");
  $cfg_buttons->g_grid (-column => 0, -row => 2, -padx => '5 5', -pady => '5 5', -sticky => "nwes");

  # Path
  $cfg_path->g_grid_columnconfigure(0, -weight => 0);
  $cfg_path->g_grid_columnconfigure(1, -weight => 1);
  $cfg_path->g_grid_columnconfigure(2, -weight => 0);
  $cfg_path->g_grid_rowconfigure   (0, -weight => 1);
  $cfg_path->g_grid_rowconfigure   (1, -weight => 1);
  $cfg_path->g_grid_rowconfigure   (2, -weight => 1);
  $tlgpath_l->g_grid(-column => 0, -row => 0, -padx => '5 5', -pady => '2 2',  -sticky => "nsw");
  $tlgpath_e->g_grid(-column => 1, -row => 0, -padx => '5 5', -pady => '2 2', -sticky => "nswe");
  $tlgpath_b->g_grid(-column => 2, -row => 0, -padx => '5 5', -pady => '2 2', -sticky => "nse");
  $phipath_l->g_grid(-column => 0, -row => 1, -padx => '5 5', -pady => '2 2', -sticky => "nsw");
  $phipath_e->g_grid(-column => 1, -row => 1, -padx => '5 5', -pady => '2 2', -sticky => "nswe");
  $phipath_b->g_grid(-column => 2, -row => 1, -padx => '5 5', -pady => '2 2', -sticky => "nse");
  $ddppath_l->g_grid(-column => 0, -row => 2, -padx => '5 5', -pady => '2 2', -sticky => "nsw");
  $ddppath_e->g_grid(-column => 1, -row => 2, -padx => '5 5', -pady => '2 2', -sticky => "nswe");
  $ddppath_b->g_grid(-column => 2, -row => 2, -padx => '5 5', -pady => '2 2', -sticky => "nse");

  # Settings
  $cfg_settings->g_grid_columnconfigure(0, -weight => 1);
  $cfg_settings->g_grid_columnconfigure(1, -weight => 1);
  $cfg_settings->g_grid_columnconfigure(2, -weight => 1);
  $cfg_settings->g_grid_columnconfigure(3, -weight => 1);
  $cfg_settings->g_grid_rowconfigure   (0, -weight => 1);
  $cfg_settings->g_grid_rowconfigure   (1, -weight => 1);
  $cfg_settings->g_grid_rowconfigure   (2, -weight => 1);
  $search_l->g_grid         (-column => 0, -row => 0, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $search_cbb->g_grid       (-column => 1, -row => 0, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $synonyma_cbtn->g_grid    (-column => 2, -row => 0, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $continentia_cbtn->g_grid (-column => 3, -row => 0, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $corpus_l->g_grid         (-column => 0, -row => 1, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $corpus_cbb->g_grid       (-column => 1, -row => 1, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $threshold_l->g_grid      (-column => 2, -row => 1, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $threshold_sb->g_grid     (-column => 3, -row => 1, -padx => '5 5', -pady => '5 5', -sticky => 'nwes');
  $lang_l->g_grid           (-column => 0, -row => 2, -padx => '5 5', -pady => '8 5', -sticky => 'nwes');
  $lang_cbb->g_grid         (-column => 1, -row => 2, -padx => '5 5', -pady => '8 5', -sticky => 'nwes');
  $browsercolumns_l->g_grid (-column => 2, -row => 2, -padx => '5 5', -pady => '8 5', -sticky => 'nwes');
  $browsercolumns_sb->g_grid(-column => 3, -row => 2, -padx => '5 5', -pady => '8 5', -sticky => 'nwes');

  # Buttons
  $cfg_buttons->g_grid_columnconfigure(0, -weight => 1);
  $cfg_buttons->g_grid_columnconfigure(1, -weight => 1);
  $cfg_buttons->g_grid_rowconfigure   (0, -weight => 1);
  $cfg_cancel_bttn->g_grid(-column => 0, -row => 0, -pady => '5 5', -padx => '5 5', -sticky => 'nwes');
  $cfg_bttn->g_grid       (-column => 1, -row => 0, -pady => '5 5', -padx => '5 5', -sticky => 'nwes');

  # Destroy window properly
  $cfg->g_wm_protocol("WM_DELETE_WINDOW" => $cancel_cfg);

  if ($arg) {
    Tkx::MainLoop();
  }
}
#------------------------------------------------
# VIEW SINGLE RESULTS
#------------------------------------------------

sub view_single_results {
  # get currently selected entrie(s)
  get_selection();
  error( $ls{error_select} ) && return
    unless @selected_str;

  # window definition
  my $viewer = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $viewer->g_wm_title($ls{single_results});
  $viewer->g_wm_iconphoto('icon');

  my $viewer_m = $viewer->new_menu();
  $viewer->configure(-menu => $viewer_m);

  my $viewer_txt = $viewer->new_tk__text
  (
   -width  => 62,
   -height => 20,
   -font   => 'TkTextFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   #  -bg     => 'gray85',
   -border => 0,
   -spacing3 => 2,
   -exportselection => 1,
  );
  $open_viewers{$viewer_txt} = [ @selected_num ];
  my $viewer_scroll = $viewer->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$viewer_txt, 'yview']
  );
  $viewer_txt->configure(-yscrollcommand => [$viewer_scroll, 'set']);
  $viewer_scroll->g___autoscroll__autoscroll() if $autoscroll;

  my $destroy_viewer = sub {
    $printer_interrupt = 1;
    Tkx::after( 30, sub { delete $textframes{$viewer_txt};
			  delete $open_viewers{$viewer_txt};
			  $printer_interrupt = 0;
			  $viewer->g_destroy();
			} );
  };
  my $viewer_bttn = $viewer->new_ttk__button
    (-text => $ls{close},
     -command => $destroy_viewer
    );
  $viewer->g_wm_protocol("WM_DELETE_WINDOW" => $destroy_viewer);

  $viewer->g_grid_columnconfigure(0, -weight => 1);
  $viewer->g_grid_columnconfigure(1, -weight => 0);
  $viewer->g_grid_rowconfigure   (0, -weight => 1);
  $viewer->g_grid_rowconfigure   (1, -weight => 0);
  $viewer_txt->g_grid   (-column => 0, -row => 0, -pady => '5 5', -sticky => "nwes");
  $viewer_scroll->g_grid(-column => 1, -row => 0, -pady => '5 5', -sticky => "nwes");
  $viewer_bttn->g_grid(-column => 0, -row => 1, -pady => '5 5');

  # Key Bindings
  my $viewer_txt_scale   = set_text_font();
  $viewer_txt->g_bind('<Control-plus>',        [\&$viewer_txt_scale, '1'] );
  $viewer_txt->g_bind('<Control-KP_Add>',      [\&$viewer_txt_scale, '1'] );
  $viewer_txt->g_bind('<Control-minus>',       [\&$viewer_txt_scale, '-1'] );
  $viewer_txt->g_bind('<Control-KP_Subtract>', [\&$viewer_txt_scale, '-1'] );

  # Tags
  $viewer_txt->tag_configure
    ("header",
     -foreground => '#3E7804',
    );
  $viewer_txt->tag_configure
    ("matched",
     -background => "yellow",
    );
  $viewer_txt->tag_configure
    ("info",
     -foreground => 'gray',
    );

  $viewer_txt->g_bind('<Configure>', \&update_separator_width);

  # clear old data
  for my $tag ( split ' ', $viewer_txt->tag_names() ) {
    $viewer_txt->tag_delete("$tag") if
      $tag =~ /^[ts]\d+/;
  }

  # insert the contents
  my $output_str = '';
  my @location;
  # get the tlg numbers in chronological order
  my @ordered_nums = @{ $tlg_lister->{tlg_ordered_authnums} };
  s/^.*$/tlg$&.txt/ for @ordered_nums;

  for my $index (@selected_num) {
    my @ordered_result_keys = ();
    for (@ordered_nums) {
      push @ordered_result_keys, $_ if exists $words[$index]{seen_all}{$_} ;
    }
    for my $tlg_number (@ordered_result_keys) {
      my $number = substr $tlg_number, 3, 4;
      for my $match ( @{ $words[$index]{seen_all}{$tlg_number} }  ) {
	# print skipped by Diogenes should be remembered so that the
	# can properly deleted in the GUI
	if ( exists $words[$index]{not_printed}{$tlg_number}{$match} ) {
	  push @{ $location[-1]{not_printed} }, $match;
	  next;
	}
	my %hash =
	  (author => $number,
	   match  => $match,
	   word   => $index,
	  );
	push @location, \%hash;
      }
    }
    $output_str .= ${$words[$index]{result}}
  }
  print_results(\$output_str, $viewer_txt, \@location, $viewer_m);
}

#------------------------------------------------
# PATTERN EDITOR
#------------------------------------------------

sub edit_patterns {
  my $w = shift;
  return if exists $words[$w]{pattern_ed};
  $words[$w]{pattern_ed} = 1;
  my $stem_min = $g_stem_min;
  my $max_alt = $g_max_alt;
  my $chop_optional_groups = $g_chop_optional_groups;

  return unless exists $words[$w]{forms};
  my @patterns = @{ $words[$w]{forms} };

  my $pattern_ed = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $pattern_ed->g_wm_title($ls{pattern_ed});
  $pattern_ed->g_wm_iconphoto('icon');

  my $pattern_txt_height = ( @patterns > 20 )
    ? 20 * 2
    : @patterns * 2;
  my $pattern_ed_txt = $pattern_ed->new_tk__text
  (
   -width  => 62,
   -height => $pattern_txt_height,
   -font   => 'TkFixedFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'char',
   -border => 0,
   -spacing3 => 10,
  );
  my $pattern_ed_scroll = $pattern_ed->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$pattern_ed_txt, 'yview']
  );
  $pattern_ed_txt->configure(-yscrollcommand => [$pattern_ed_scroll, 'set']);
  $pattern_ed_scroll->g___autoscroll__autoscroll() if $autoscroll;

  my $destroy_pattern_ed = sub {
    delete $words[$w]{pattern_ed};
    $pattern_ed->g_destroy();
  };
  $pattern_ed->g_wm_protocol("WM_DELETE_WINDOW" => $destroy_pattern_ed);
  my $pattern_ed_bttn = $pattern_ed->new_ttk__button
    (-text => $ls{cancel},
     -command => $destroy_pattern_ed,
    );

  # my $pattern_ed_change_bttn = $pattern_ed->new_ttk__button
  #   (-text => $ls{change},
  #    -command => sub {
  #      $words[$w]{restart} = 1;
  #      &$destroy_pattern_ed();
  #      }
  #   );

  # $stats_context_sb = $stats_bttn_context_frm->new_ttk__spinbox
  # (
  #  -from => 1.0,
  #  -to   => 100.0,
  #  -textvariable => \$context,
  #  -state => 'normal',
  #  -width => 4,
  #  -command => \&context_sb_callback,
  #  -validate => 'all',
  #  -validatecommand => [ \&is_numeric, Tkx::Ev('%P')]
  # );
  # $st_cbt_syn = $input_bttn_frm->new_ttk__checkbutton
  # (
  #  -text => $ls{synonyma},
  #  -command => sub {   },
  #  -variable => \$select_st_synonyma,
  # );

  $pattern_ed->g_grid_columnconfigure(0, -weight => 1);
  $pattern_ed->g_grid_columnconfigure(1, -weight => 0);
  $pattern_ed->g_grid_rowconfigure   (0, -weight => 1);
  $pattern_ed->g_grid_rowconfigure   (1, -weight => 0);
  $pattern_ed_txt->g_grid   (-column => 0, -row => 0, -pady => '5 5', -sticky => "nwes");
  $pattern_ed_scroll->g_grid(-column => 1, -row => 0, -pady => '5 5', -sticky => "nwes");
  $pattern_ed_bttn->g_grid(-column => 0, -row => 1, -pady => '5 5');

  # Key Bindings
  my $pattern_ed_txt_scale   = set_text_font();
  $pattern_ed_txt->g_bind('<Control-plus>',        [\&$pattern_ed_txt_scale, '1'] );
  $pattern_ed_txt->g_bind('<Control-KP_Add>',      [\&$pattern_ed_txt_scale, '1'] );
  $pattern_ed_txt->g_bind('<Control-minus>',       [\&$pattern_ed_txt_scale, '-1'] );
  $pattern_ed_txt->g_bind('<Control-KP_Subtract>', [\&$pattern_ed_txt_scale, '-1'] );

  # Tags
  $pattern_ed_txt->tag_configure
    ("count",
     #-foreground => '#3E7804',
     -font => [-weight => 'bold', -size => $normal_size],
    );
  $pattern_ed_txt->tag_configure
    ("pipe",
     -foreground => "red",
    );
  $pattern_ed_txt->tag_configure
    ("paren",
     -foreground => 'green',
    );
  $pattern_ed_txt->tag_configure
    ("optional",
     -foreground => 'purple',
    );

  # insert the pattern
  my $i = 1;
  for my $pattern (@patterns) {
    # get positions of syntax markers
    my (@pipes, @parens, @optionals);
    my $count_len = length($i) + 2;
    while ($pattern =~ /\|/g) {
      my $end = pos($pattern) + $count_len;
      push @pipes, $end;
    }
    while ($pattern =~ /\(|\)/g) {
      my $end = pos($pattern) + $count_len;
      push @parens, $end;
    }
    while ($pattern =~ /\?/g) {
      my $end = pos($pattern) + $count_len;
      push @optionals, $end;
    }

    # insert the text
    $pattern_ed_txt->insert("end", "$i: $pattern\n");

    # apply the tags
    $pattern_ed_txt->tag_add("count", "$i.0", "$i.$count_len");
    for my $end (@pipes) {
      my $start = $end - 1;
      $pattern_ed_txt->tag_add("pipe", "$i.$start", "$i.$end");
    }
    for my $end (@parens) {
      my $start = $end - 1;
      $pattern_ed_txt->tag_add("paren", "$i.$start", "$i.$end");
    }
    for my $end (@optionals) {
      my $start = $end - 1;
      $pattern_ed_txt->tag_add("optional", "$i.$start", "$i.$end");
    }
    $i++;
  }
  $pattern_ed_txt->delete("end-1l", "end");
  $pattern_ed_txt->configure(-state => 'disabled');
}

#------------------------------------------------
# BROWSER
#------------------------------------------------

sub invoke_browser {
  my $auth   = shift;
  my $offset = shift;
  my $browser_w = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $browser_w->g_wm_title($ls{browser});
  $browser_w->g_wm_iconphoto('icon');

  # MAIN FRAME
  my $browser_frm = $browser_w->new_tk__frame
    (
     -background => 'white'
     # -padding => "12 12 12 12",
    );

  $browser_w->g_grid_columnconfigure(0, -weight => 1);
  $browser_w->g_grid_rowconfigure   (0, -weight => 1);

  $browser_frm->g_grid (-column => 0, -row => 0, -sticky => "nwes");

  $browser_frm->g_grid_rowconfigure   (0, -weight => 0);
  $browser_frm->g_grid_rowconfigure   (1, -weight => 1);
  $browser_frm->g_grid_rowconfigure   (1, -weight => 0);

  my $header_txt = $browser_frm->new_tk__text
    (
     #    -width  => 70,
     -height => 4,
     -font   => 'TkCaptionFont',
     # -padx   => 5,
     # -pady   => 5,
     -wrap   => 'word',
     #  -bg     => 'gray85',
     -borderwidth => 20,
     -relief => 'flat',
     -spacing3 => 2,
     -insertborderwidth => 0,
     -highlightthickness => 0,
    );
  $header_txt->tag_configure
    ("header",
     -foreground => '#3E7804',
     -justify => "center",
    );

  $header_txt->g_grid(-column => 1, -columnspan => ($browser_column_count + 1),
		      -row => 0, -sticky => "news");

  my (@browser_txtfrm, @browser_txt, @citation_txt);
  for my $i (0..$browser_column_count) {
    $browser_frm->g_grid_columnconfigure($i + 1, -weight => 1);
    # Frame.for both citation and text
    $browser_txtfrm[$i] = $browser_frm->new_tk__frame(-background => 'white', -padx => 5);
    $browser_txtfrm[$i]->g_grid_columnconfigure(0, -weight => 1);
    $browser_txtfrm[$i]->g_grid_columnconfigure(1, -weight => 0);
    $browser_txtfrm[$i]->g_grid
      (-column => $i + 1, -row => 1,  -sticky => "nwes");

    #citation
    $citation_txt[$i] = $browser_txtfrm[$i]->new_tk__text
      (
       -width  => 3,
       -height => 30,
       -font   => 'TkTextFont',
       -wrap   => 'none',
       -foreground => 'gray',
       -borderwidth => 3,
       -relief => 'flat',
       -spacing3 => 2,
       -insertborderwidth => 0,
       -highlightthickness => 0,
       -selectbackground => 'white',
       -selectforeground => 'gray',
      );
    $citation_txt[$i]->g_grid(-column => 0, -row => 0, -sticky => "nwes");
    # make citation not selectable
    $citation_txt[$i]->g_bind
      ('<<Selection>>',
       sub {
	 $citation_txt[$i]->tag_remove('sel', '1.0', 'end')
	   if $citation_txt[$i]->tag_ranges('sel');
       }
      );

    #text
    $browser_txt[$i] = $browser_txtfrm[$i]->new_tk__text
      (
       -width  => 3,
       -height => 30,
       -font   => 'TkTextFont',
       -wrap   => 'none',
       -borderwidth => 3,
       -relief => 'flat',
       -spacing3 => 2,
       -insertborderwidth => 0,
       -highlightthickness => 0,
      );
    $browser_txt[$i]->g_grid(-column => 1, -row => 0, -sticky => "nwes");
  }

  # Movement Buttons
  my $backward_bttn = $browser_frm->new_ttk__button
    (-text => "←",
     -width => 3,
    );

  my $forward_bttn = $browser_frm->new_ttk__button
    (-text => "→",
     -width => 3,
    );

  $backward_bttn->g_grid (-column => 0, -row => 1);
  $forward_bttn->g_grid  (-column => $browser_column_count + 2, -row => 1);
  $browser_frm->g_grid_columnconfigure(0, -weight => 0);
  $browser_frm->g_grid_columnconfigure($browser_column_count + 2, -weight => 0);

  # Close Button
  my $browser_close_bttn = $browser_frm->new_ttk__button
    (-text => $ls{close},
     -command => sub { $browser_w->g_destroy(); }
    );
  $browser_close_bttn->g_grid(-column => 1, -columnspan => ($browser_column_count + 1),
			      -row => 2, -pady => '10 10');


  # Load data
  $auth          = $tlg_browser->parse_idt($auth);
  my $work       = $tlg_browser->get_work($auth, $offset);
  my @work_begin = $tlg_browser->seek_passage($auth, $work);
  my $start      = $tlg_browser->get_relative_offset($offset, $auth, $work);

  @browser_buffers = ();
  @browser_headers = ();
  @browser_indices = ();

  # Browe object to be passed to the callbacks and functions
  my $browser =
    {
     header_txt    => $header_txt,
     browser_txt   => \@browser_txt,
     citation_txt  => \@citation_txt,
     forward_bttn  => $forward_bttn,
     backward_bttn => $backward_bttn,
    };

  # Load the passage
  {
    my ($buf, @ind);
    local *STDOUT;
    open STDOUT, '>:raw', \$buf;
    @ind = $tlg_browser->browse_half_backward($start, -1);
    my $times = ($browser_column_count) / 2;
    for (1..$times) {
      $buf = '';
      open STDOUT, '>:raw', \$buf;
      @ind = $tlg_browser->browse_backward(@ind);
    }
    unshift @browser_buffers, \$buf;
    unshift @browser_indices, \@ind;

    browser_browse($browser_column_count);
    browser_insert_contents($browser);
  }

  # mark the line containing the end of the first match
  my $marked = ($browser_column_count) / 2;
  $browser_txt[$marked]->tag_add('sel', '13.0', '14.0');

  # KEY Bindings, button callbacks, scale callbacks
  $forward_bttn->configure (-command => [\&browse_forward,  $browser]);
  $backward_bttn->configure(-command => [\&browse_backward, $browser]);

  $browser_w->g_bind('<Prior>', sub { browse_backward($browser)
					for 0..$browser_column_count });
  $browser_w->g_bind('<Next>', sub { browse_forward($browser)
				       for 0..$browser_column_count });
  $browser_w->g_bind('<Left>',  [ \&browse_backward, $browser ]);
  $browser_w->g_bind('<Right>', [ \&browse_forward,  $browser ]);
  $browser_w->g_bind('<Home>',  [ \&browse_begin,    $browser ]);
  $browser_w->g_bind('<End>',   [ \&browse_end,      $browser ]);
  $browser_w->g_bind('<Escape>', sub{ $browser_w->g_destroy() });
  $browser_w->g_bind('<q>',      sub{ $browser_w->g_destroy() });

  my $text_font_size = $normal_size;
  my $browser_txt_scale = sub {
    my $num = shift;
    my $active = Tkx::focus();
    $text_font_size = ($text_font_size + $num > 5)
      ? $text_font_size + $num
      : 5;
    if ($gentium_available) {
      $header_txt->configure
	(-font => [-family => 'Gentium', -size => "$text_font_size"]);
      for my $i (0..$#browser_txt) {
	$citation_txt[$i]->configure
	  (-font => [-family => 'Gentium', -size => "$text_font_size"]);
	$browser_txt[$i]->configure
	  (-font => [-family => 'Gentium', -size => "$text_font_size"]);
      }
    }
    else {
      $header_txt->configure
	(-font => [-size => "$text_font_size"]);
      for my $i (0..$#browser_txt) {
	$citation_txt[$i]->configure(-font => [-size => "$text_font_size"]);
	$browser_txt[$i]->configure(-font => [-size => "$text_font_size"]);
      }
    }
  };
  $browser_w->g_bind('<Control-plus>',   [\&$browser_txt_scale, '1'] );
  $browser_w->g_bind('<Control-KP_Add>', [\&$browser_txt_scale, '1'] );
  $browser_w->g_bind('<Control-minus>',  [\&$browser_txt_scale, '-1'] );
  $browser_w->g_bind('<Control-KP_Subtract>', [\&$browser_txt_scale, '-1'] );
}

sub browser_browse {
  my $count   = shift;
  my $backwards;
  if ($count == 0) { return }
  elsif ($count < 0) {
    $backwards = 1;
    $count = -$count;
  }

  for (1..$count) {
    local *STDOUT;
    my ($buf, @ind);
    open STDOUT, '>:raw', \$buf;
    unless ( $backwards ) {
      @ind = $tlg_browser->browse_forward(@{ $browser_indices[-1] });
      return -1 if $ind[1] == -1;
 #     say STDERR for @ind;
      push @browser_buffers, \$buf;
      push @browser_indices, \@ind;
      if ($#browser_buffers > $browser_column_count) {
	shift @browser_buffers; shift @browser_indices;
	say STDERR Dumper(@browser_indices);
      }
    }
    else {
      @ind = $tlg_browser->browse_backward(@{ $browser_indices[0] });
      return -1 if $ind[0] == $browser_indices[0][0];
#      say STDERR for @ind;
      unshift @browser_buffers, \$buf;
      unshift @browser_indices, \@ind;
      if ($#browser_buffers > $browser_column_count) {
	pop @browser_buffers; pop @browser_indices;
	say STDERR Dumper(@browser_indices);
      }
    }
  }
}

sub browser_insert_contents {
  my $browser = shift;
  for my $i (0..$browser_column_count) {
    $browser->{browser_txt}[$i]->configure (-state => 'normal');
    $browser->{citation_txt}[$i]->configure(-state => 'normal');
    open my $str_fh, '<:utf8', $browser_buffers[$i];
    local $/ = "\n\n";
    $browser_headers[$i] = <$str_fh>;

    my $buf = '';
    $buf .= $_ while <$str_fh>;
    # Chop beginning of the following work
    if ( (my $pos = index $buf, '/ / /') != -1) {
      $buf = substr $buf, 0, $pos;
      $buf .= "\n"
    }
    # separate the citation form the text, get length of the longest line
    my $cit = '';
    my ($bufllen, $citllen) = (0, 0);
    my @lines = split "\n", $buf;
    for (@lines) {
      s/\s+$//;
      if (s/^(\S+)\s+//mg) {
	$cit .= $1 ."\n";
	my $wlen = length($1);
	$citllen = ($citllen >= $wlen) ? $citllen : $wlen;
      }
      else {
	s/^\s+//;
	$cit .= "\n"
      }
      my $llen = length;
      $bufllen = ($bufllen >= $llen) ? $bufllen : $llen;
    }
    $bufllen -= 5;
    $buf = join "\n", @lines;
    $browser->{citation_txt}[$i]->delete("1.0", "end");
    $browser->{citation_txt}[$i]->insert("end", $cit);
    $browser->{citation_txt}[$i]->delete("end-1l", "end");
    $browser->{citation_txt}[$i]->configure(-width => $citllen,
					    -state => 'disabled');

    $browser->{browser_txt}[$i]->delete("1.0", "end");
    $browser->{browser_txt}[$i]->insert("end", $buf);
    $browser->{browser_txt}[$i]->delete("end-1l", "end");
    $browser->{browser_txt}[$i]->configure (-width => $bufllen,
					    -state => 'disabled');
  }
  $browser->{header_txt}->configure(-state => 'normal');
  $browser->{header_txt}->delete("1.0", "end");
  $browser->{header_txt}->insert("end", $browser_headers[0]);
  $browser->{header_txt}->delete("end-1l", "end");
  $browser->{header_txt}->tag_add("header", "1.0", "end");
  $browser->{header_txt}->configure(-state => 'disabled');
}

sub browse_forward {
  my $browser = shift;
  my $r = browser_browse(1);
  unless ($r == -1) {
    $browser->{forward_bttn}->state("!disabled");
    $browser->{backward_bttn}->state("!disabled");
    browser_insert_contents($browser);
  }
  else {
    $browser->{forward_bttn}->state("disabled");
  }
}

sub browse_begin {
  my $browser = shift;
  until (browser_browse(-1) == -1) { };
  $browser->{backward_bttn}->state("disabled");
  $browser->{forward_bttn}->state("!disabled");
  browser_insert_contents($browser);
}

sub browse_end {
  my $browser = shift;
  until (browser_browse(1) == -1) { };
  $browser->{forward_bttn}->state("disabled");
  $browser->{backward_bttn}->state("!disabled");
  browser_insert_contents($browser);
}

sub browse_backward {
  my $browser = shift;
  my $r = browser_browse(-1);
  unless ($r == -1) {
    $browser->{forward_bttn}->state("!disabled");
    $browser->{backward_bttn}->state("!disabled");
    browser_insert_contents($browser);
  }
  else {
    $browser->{backward_bttn}->state("disabled");
  }
}


#------------------------------------------------
# BLACKLIST EDITOR

#------------------------------------------------
# EXPORT FUNCTIONS
#------------------------------------------------

sub export_to_text {
  my $txt      = shift;

  my $lmark  = '-->';
  my $rmark  = '<--';
  my $hstartl = '';
  my $hstartr = '';
  my $hend   = "\n";
  my $istart = '';
  my $iend   = '';

  my $maxline = 62;
  my $separator = '=' x $maxline;
  my $firstcol = $maxline - 24;

  my $center = sub {
    my $str = shift;
    my $pad = int(($maxline - length($str)) / 2);
    $str = ' ' x $pad . $str;
    return $str;
  };

  # Add export header
  my $title = ($txt eq $results_txt) ? "LYNKEUS REPORT" : $ls{single_results};
  my $date = date();

  my $header = '';
  if ($txt eq $results_txt) {
    my @input_lines = split /\n/,
      $input_txt->get("1.0", "end");
    for my $line (@input_lines) {
      breakline(\$line, $maxline);
    }
    my $text = join "\n", @input_lines;
    my @statistics = get_statistics();
    my $searchtype = ($st_lemma)
      ? $ls{lemma} : $ls{verbatim};
    my $context_type = get_context_type_str();

    $header .= "$separator\n";
    $header .= $center->($title) . "\n";
    $header .= $center->($date) . "\n";
    $header .= "$separator\n";
    $header .= sprintf "%-38s%12s%12s\n", @{ shift @statistics };
    while (@statistics) {
      my ($terminus, $hits, $weight) = @{ shift @statistics };
      $terminus =~ s/^([^(]+)\(.*$/$1/;
      $header .= sprintf "%-38s%12d%12d\n", $terminus, $hits, $weight;
    }

    $header .= "$separator\n";
    $header .= sprintf "%-31s%31s\n",
      "$ls{search_type}: $searchtype",
      "$ls{context}: $context $context_type";
    $header .= sprintf "%-31s%31s\n",
      "$ls{search_in}: $si_corpus",
      "$ls{threshold}: $threshold";
    $header .= "$separator\n";
  }
  else {
    my (@viewed_words, $text);
    for my $index (@{ $open_viewers{$txt} }) {
      ($st_lemma)
	? push @viewed_words, $words[$index]{lemma}
	: push @viewed_words, $words[$index]{word};
    }
    $header .= "$separator\n";
    $header .= $center->($title) . "\n";
    $header .= $center->($date) . "\n";
    $header .= $center->($_) . "\n" for @viewed_words;
    $header .= "$separator\n";
  }

  $separator = "\n$separator\n\n";
  my $output = export( $txt, $header, $lmark, $rmark,
		       $hstartl, $hstartr, $hend, $istart, $iend,
		       $separator, $maxline );
  return $output;
}

sub export_to_mom {
  my $txt      = shift;

  my $lmark   = '\\*[BD]';
  my $rmark   = '\\*[PREV]';

  my $hstartl = ".FT B\n" . ".COLOR green\n";
  my $hstartr = "\n.SP 2p" . "\n.COLOR black";

  my $hend    = "\n.SP 6p" . "\n.FT R";
  my $istart  = ".SP 2p\n" . ".FT R\n" . ".COLOR gray\n";
  my $iend    = "\n.COLOR black";

  my $separator = ".SP 2p\n" . ".DRH\n" . ".SP 2p\n" . "\n";
  my $maxline = 82;

  my $title = ($txt eq $results_txt) ? "LYNKEUS REPORT" : $ls{single_results};
  $title = uc $title;
  my $date  =  date();
  my $header = <<EOT;
.TITLE "$title"
.SUBTITLE "$date"
.PRINTSTYLE TYPESET
.PAPER A4
.FAMILY GentiumPlus
.FT R
.NEWCOLOR green RGB #3E7804
.NEWCOLOR gray  RGB #808080
.HEADER_LEFT "$date"
.HEADER_CENTER "###"
.HEADER_RIGHT "$title"
.HY OFF
.START
.LEFT

EOT

  if ($txt eq $results_txt) {
    my @input_lines = split /\n/,
      $input_txt->get("1.0", "end");
    my $header_center = $input_lines[0];
    $header_center =~ s/^((?:\s*\S+){0,5}).*/$1/;
    ($header_center, undef) =
      split /[.,·;]/, $header_center, 2;
    $header =~ s/###/$header_center/;

    $header .= ".BOX OUTLINED black\n";
    $header .= ".PP\n";
    $header .= "$_\n.BR\n" for @input_lines;
    $header .= ".BOX END\n";

    my @statistics = get_statistics();
    my $searchtype = ($st_lemma)
      ? $ls{lemma} : $ls{verbatim};
    my $context_type = get_context_type_str();
    $header .= ".TS\n";
    $header .= "expand;\n";
    $header .= "l r 1 r.\n";
    my $firstrow = shift @statistics;
    for my $item (@$firstrow) {
      $header .= "$item\t";
    }
    $header .= "\n" . "_\n" . ".SP 4p\n";
    for my $line (@statistics) {
      for my $item (@$line) {
	$header .= "$item\t";
      }
      $header .= "\n";
    }
    $header .= <<EOT;
_
.TE
.RLD 10p
.MCO
.LEFT
$ls{search_type}: $searchtype
$ls{context}: $context $context_type
.MCR
.RIGHT
$ls{search_in}: $si_corpus
$ls{threshold}: $threshold
.MCX
.RLD 10p
.DRH 2 0p \\n[.l]u black
.LEFT


EOT
  }
  else {
    my (@viewed_words, $text);
    for my $index (@{ $open_viewers{$txt} }) {
      ($st_lemma)
	? push @viewed_words, $words[$index]{lemma}
	: push @viewed_words, $words[$index]{word};
    }
    my $headline = $viewed_words[0];
    for my $i (1..$#viewed_words) {
      $headline .= "..." and last if $i > 2;
      my $nextword = $viewed_words[$i];
      $nextword =~ s/^([^(]+)\(.*$/$1/;
      $headline .= ", $nextword"
    }
    $header =~ s/###/$headline/;
    $header .= ".CENTER\n";
    $header .= "$_\n" for @viewed_words;
    $header .= ".DRH 2 0p \\n[.l]u black\n";
    $header .= ".LEFT\n";
    $header .= "\n\n";
  }

  my $output = export( $txt, $header, $lmark, $rmark,
		       $hstartl, $hstartr, $hend, $istart, $iend,
		       $separator, $maxline );

  $output =~ s/;/;/g;
  return $output;
}

sub date {
  my (undef,undef,undef,$day,$mon,$year) = localtime;
  $year += 1900;
  $mon += 1;
  return my $date = sprintf "%d.%d.%d", $day, $mon, $year;
}

sub get_statistics {
  my @items = split ' ', $stats_tw->children('');
  my @columns = ($ls{search_term}, $ls{numberofhits}, $ls{weight}) ;
  for my $i (0..$#items) {
    my $item   = $items[$i];
    my $text   = $stats_tw->item($item, '-text');
    my $hits   = $stats_tw->set ($item, 'hits');
    my $weight = $stats_tw->set ($item, 'weight');
    $items[$i] = [ $text, $hits, $weight ];
  }
  unshift @items, \@columns;
  return @items;
}

sub breakline {
  my $ref = shift;
  my $max = shift;
  my $length = length $$ref;
  my $pos = 0;
  my @newlines;

  while ($length - $pos > $max) {
    $pos += $max;
    --$pos until substr($$ref, $pos, 1) eq ' ';
    push @newlines, $pos;
  }
  for my $n (reverse @newlines) {
    $$ref = substr($$ref, 0, $n - 1) . "\n" . substr($$ref, $n + 1)
  }
}

sub export {
  my ($txt, $header,
      $lmark, $rmark,
      $hstartl, $hstartr, $hend,
      $istart, $iend,
      $separator, $maxline) = @_;

  my $i = 0;
  my %lines = map { ++$i, $_ }
    split "\n", $txt->get('1.0', 'end');
  $lines{0} = $header;

  # Apply formatting for the matched tag
  my @matched = split ' ', $txt->tag_ranges('matched');
  @matched = map { my @array = split /\./, $_; \@array } @matched;
  # filter out the hits split over two lines
  {
    my @indices = 1..($#matched - 1);
    my @retained = (0);
    while (@indices) {
      my $end = shift @indices; my $start = shift @indices;
      next if ( $matched[$start][1] == 0
		and $matched[$end][0] + 1 == $matched[$start][0]
		and $matched[$end][1] == length $lines{$matched[$end][0]} );
      push @retained, $end, $start;
    }
    push @retained, $#matched;
    @matched = @matched[@retained];
  }

  @matched = reverse @matched;
  while (@matched) {
    my ($endline,   $endoffset)   = @{ shift @matched };
    $lines{$endline} =
      substr($lines{$endline}, 0, $endoffset) .
      $rmark .
      substr($lines{$endline}, $endoffset);
    my ($startline, $startoffset) = @{ shift @matched };
    $lines{$startline} =
      substr($lines{$startline}, 0, $startoffset) .
      $lmark .
      substr($lines{$startline}, $startoffset);
  }

  # Apply formatting for the header tag
  my @header = split ' ', $txt->tag_ranges('header');
  while (@header) {
    my ($startline, undef) = split /\./,  shift @header;
    my ($endline,   undef) = split /\./, shift @header;
    for my $line ($startline..$endline) {
      breakline( \$lines{$line}, $maxline )
	if length($lines{$line}) > $maxline;
    }
    # $lines{$startline} = "\n" . $lines{$startline};
    $lines{$startline} =~ s/^\s+//;
    $lines{$startline} =  $hstartl . $lines{$startline} . $hstartr;
    $lines{$endline}  .=  $hend;
  }

  # Apply formatting for the info tag
  my @info = split ' ', $txt->tag_ranges('info');
  while (@info) {
    my ($startline, undef) = split /\./, shift @info;
    my ($endline,   undef) = split /\./, shift @info;
    $lines{$_} =~ s/\t/ /g for ($startline..$endline);
    $lines{$startline} =  $istart . $lines{$startline};
    $lines{$endline}  .=  $iend;
  }

  # Add separator lines
  for my $count (0..$#{ $textframes{$txt} }) {
    my ($line, undef) = split /\./, $txt->tag_ranges("s$count");
    $lines{$line} = $separator if $line;
  }

  # Delete elided passages
  my %elided;
  for my $count (0..$#{ $textframes{$txt} }) {
    next unless $txt->tag_cget("t$count", '-elide');
    my @ranges = split ' ', $txt->tag_ranges("t$count");
    @ranges = map { s/(\d+).*/$1/r } @ranges;
    $elided{$_} = 1 for $ranges[0]..$ranges[1];
  }

  # Restrict output to selection if there is one
  my @selected = split ' ', $txt->tag_ranges("sel");
  my %selected;
  while (@selected) {
    my ($startline, undef) = split /\./, shift @selected;
    my ($endline,   undef) = split /\./, shift @selected;
    for my $num ($startline..$endline) {
      $selected{$num} = 1;
    }
  }

  my $output = '';
  for my $num (sort numerically keys %lines) {
    next if $elided{$num};
    if (%selected) { next unless $selected{$num} }
    $output .= $lines{$num} . "\n";
  }

  return $output;
}

sub groff {
  my $output = shift;
  my $filename = shift;
  my $parent = shift // $mw;
  (undef, my $src) = tempfile (OPEN => 0, CLEANUP => 0);
  say $src;
  open my $fh, '>:utf8', $src or warn "Cannot open tempfile $src: $!";
  print { $fh } $output;
  close $fh;
  (undef, my $log) = tempfile (OPEN => 0, CLEANUP => 0);
  my $pid = fork;
  unless ($pid) {
    exec "groff -mmom -Kutf8 -Tpdf -t $src 1> $filename 2> $log"
  }
  # my $pid = open my $fh, '|-:utf8',
  #   "groff -mmom -Kutf8 -Tpdf -t > $filename 2> $log"
  #   or error("Could not pipe to groff: $!");
  # say { $fh } $output;
  # close $fh;
  Tkx::after( 5, [\&wait_for_groff, $pid, $log, $src, $parent] );
}

sub wait_for_groff {
  my ($pid, $log, $src, $parent) = @_;
  my $res = waitpid($pid, WNOHANG);
  if ($res == -1 or $res == $pid) {
    my $retval = $? >> 8;
    $parent = $parent->g_winfo_exists() ? $parent : $mw;

    # get stderr output
    my $logstr = '';
    if ( open my $log_fh, '<', $log ) {
      local $/ = undef;
      $logstr = <$log_fh>;
      close $log_fh; unlink $log;
    }
    else {
      warn "Could not open log: $!"
    }
    unlink $src;

    # Normal exit
    unless ($retval) {
      if ($logstr) {
	my $yesno = Tkx::tk___messageBox
	  ( -parent => $parent,
	    -type => 'yesno',
	    -default => 'no',
	    -message => "$ls{groff_success} $ls{log}"
	  );
	if ($yesno eq 'yes') {
	  view_txt($logstr, $parent, 92);
	}
      }
      else {
	Tkx::tk___messageBox
	  ( -parent => $parent,
	    -type => 'ok',
	    -message => $ls{groff_success}
	  );
      }
    }
    else {
      # Error
      if ($logstr) {
	my $yesno = Tkx::tk___messageBox
	  ( -parent => $parent,
	    -type => 'yesno',
	    -default => 'no',
	    -message => "$ls{groff_failure} (Exit code $retval) $ls{log}"
	  );
	if ($yesno eq 'yes') {
	  view_txt($logstr, $parent, 92);
	}
      }
      else {
	Tkx::tk___messageBox
	  ( -parent => $parent,
	    -type => 'ok',
	    -message => "$ls{groff_failure} (Exit code $retval)"
	  );
      }
    }
  }
  elsif ( $res == 0 ) {
    Tkx::after( 100, [\&wait_for_groff, $pid, $log, $src, $parent] );
  }
  else {
    die "Waitpid should return either $pid, 0 or -1, but returns $res!"
  }
}

#------------------------------------------------
# TEXT VIEWER
sub view_txt {
  my $str    = shift;
  my $parent = shift;
  my $width = shift // 62;
    # window definition
  my $txtview = $parent->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $txtview->g_wm_title('Info');
  $txtview->g_wm_iconphoto('icon');

  my $txtview_txt = $txtview->new_tk__text
  (
   -width  => $width,
   -height => 20,
   -font   => 'TkFixedFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   -border => 0,
   -spacing3 => 2,
   -exportselection => 1,
  );
  my $txtview_scroll = $txtview->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$txtview_txt, 'yview']
  );
  $txtview_txt->configure(-yscrollcommand => [$txtview_scroll, 'set']);
  $txtview_scroll->g___autoscroll__autoscroll() if $autoscroll;
  my $txtview_bttn = $txtview->new_ttk__button
    ( -text    => $ls{ok},
      -command => sub { $txtview->g_destroy() }
    );
  $txtview->g_grid_columnconfigure(0, -weight => 1);
  $txtview->g_grid_columnconfigure(1, -weight => 0);
  $txtview_txt->g_grid   (-column => 0, -row => 0, -pady => '5 5', -sticky => 'nwes');
  $txtview_scroll->g_grid(-column => 1, -row => 0, -pady => '5 5', -sticky => 'ns');
  $txtview_bttn->g_grid(-column => 0, -row => 1, -pady => '5 5');

  $txtview_txt->insert('1.0', $str);
}

#------------------------------------------------
# MARKDOWN VIEWER

sub view_md {
  my @paragraphs = split "\n\n", shift;
  my %h;

  # delete newlines
  s/\n/ /g for @paragraphs;

  # parse md source

  # window definition
  my $mdview = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $mdview->g_wm_title('Info');
  $mdview->g_wm_iconphoto('icon');

  my $mdview_txt = $mdview->new_tk__text
  (
   -width  => 62,
   -height => 20,
   -font   => 'TkTextFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   -border => 0,
   -spacing3 => 2,
   -exportselection => 1,
  );
  my $mdview_scroll = $mdview->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$mdview_txt, 'yview']
  );
  $mdview_txt->configure(-yscrollcommand => [$mdview_scroll, 'set']);
  $mdview_scroll->g___autoscroll__autoscroll() if $autoscroll;
}


#------------------------------------------------
# MENU FUNCTIONS

sub clear_search {
  my $answer =  Tkx::tk___messageBox
    (-type => "yesno",
     -message => $ls{message_discard},
     -default => "no",
     -icon => "question", -title => $ls{new_search});
  clear() if $answer eq 'yes';
}

sub clear {

  end_search(); edit_search();
  $input_txt->delete('1.0', 'end');
  $lemmata_cvs->g_destroy() if $lemmata_cvs;
  undef @lemmata_bttn;
  undef $lemmata_continue_bttn;

  # clear stats_tw
  my @stats_tw_items = $stats_tw->children('');
  $stats_tw->delete("@stats_tw_items");
  $results_txt->delete('1.0', 'end');

  $results_n->tab('0', -state => 'hidden');
  $results_n->tab('1', -state => 'hidden');
  $results_n->tab('2', -state => 'hidden');

  # clear menus associated with $results_txt
  clear_output_menus();

  @words = ();
  %deleted_passages = ();
  %elided_passages  = ();
}

sub save_to_file {
  error($ls{save_nothing}) and return unless @words;

  return unless my $filename = Tkx::tk___getSaveFile
    (
     -initialdir => '~',
     -defaultextension => '.lyn',
     -filetypes => [
		    [['Lynkeus'], ['.lyn']]
		   ],
    );

  # Global variables
  my $save = {};
  $save->{words}            = \@words;
  $save->{results}          = \%results;
  $save->{output}           = \%output;
  $save->{textframes}       = \%textframes;
  $save->{deleted_passages} = \%deleted_passages;
  $save->{elided_passages}  = \%elided_passages;
  # We have to delete the textframe entries of the opened viewers
  for my $viewer (keys %open_viewers) {
    delete $save->{textframes}{$viewer}
  }

  $save->{select_st_lemma}       = $select_st_lemma;
  $save->{select_st_synonyma}    = $select_st_synonyma;
  $save->{select_st_continentia} = $select_st_continentia;
  $save->{select_si_corpus}      = $select_si_corpus;
  $save->{st_lemma}              = $st_lemma;
  $save->{st_synonyma}           = $st_synonyma;
  $save->{st_continentia}        = $st_continentia;
  $save->{si_corpus}             = $si_corpus;
  $save->{context}               = $context;
  $save->{context_types_str}     = \@context_types_str;
  $save->{context_type}          = $context_type;
  $save->{context_type_str}      = $context_type_str;

  $save->{threshold}      = $threshold;
  $save->{progress_w_cnt} = $progress_w_cnt;

  $save->{selected_str}   = \@selected_str;
  $save->{selected_num}   = \@selected_num;
  $save->{weight}         = $weight;
  $save->{lemmata}        = \%lemmata;
  $save->{g_stem_min}     = $g_stem_min;
  $save->{g_max_alt}      = $g_max_alt;
  $save->{g_chop_optional_groups} = $g_chop_optional_groups;

  # State of the widgets: $input_txt
  $save->{input_txt} = $input_txt->get('1.0', 'end');

  # State of the widgets, Tab 0: Lemmata
  $save->{tab_0} = $results_n->tab('0', '-state');

  # State of the widgets, Tab 1: stats_tw
  $save->{tab_1} = $results_n->tab('1', '-state');

  # State of the widgets, Tab 2: Results
  $save->{tab_2} = $results_n->tab('2', '-state');

  # Selected tab
  $save->{tab_selected} = $results_n->select();

  eval{ store $save, $filename };
  $@ ? error  ($ls{save_failure})
     : message($ls{save_success});
}

sub load_from_file {
  return unless my $filename = Tkx::tk___getOpenFile
    (
     -initialdir => '~',
     -defaultextension => '.lyn',
     -filetypes => [
		    [['Lynkeus'], ['.lyn']]
		   ],
    );
  load($filename);
}

sub load {
  my $filename = shift;
  my $save = retrieve $filename;
  error("$ls{load_failure} $filename: $ls{load_wrong_format}") and return
    unless exists $save->{words};
  clear();

  # Clear global variables;
  $searching = 0;
  $interrupt = 0;
  $printer_interrupt = 0;

  # Reload global variables
  @words            = @{ $save->{words} };
  %results          = %{ $save->{results} };
  %output           = %{ $save->{output} };
  %textframes       = %{ $save->{textframes} };
  %deleted_passages = %{ $save->{deleted_passages} };
  %elided_passages  = %{ $save->{elided_passages} };

  $select_st_lemma       = $save->{select_st_lemma};
  $select_st_synonyma    = $save->{select_st_synonyma};
  $select_st_continentia = $save->{select_st_continentia};
  $select_si_corpus      = $save->{select_si_corpus};
  $st_lemma              = $save->{st_lemma};
  $st_synonyma 		 = $save->{st_synonyma};
  $st_continentia 	 = $save->{st_continentia};
  $si_corpus             = $save->{si_corpus};
  $context 		 = $save->{context};
  @context_types_str 	 = @{ $save->{context_types_str} };
  $context_type 	 = $save->{context_type};
  $context_type_str 	 = $save->{context_type_str};

  $threshold      = $save->{threshold};
  $progress_w_cnt = $save->{progress_w_cnt};

  @selected_str 	  = @{ $save->{selected_str} };
  @selected_num           = @{ $save->{selected_num} };
  $weight 		  = $save->{weight};
  %lemmata 		  = %{ $save->{lemmata} };
  $g_stem_min 		  = $save->{g_stem_min};
  $g_max_alt 		  = $save->{g_max_alt};
  $g_chop_optional_groups = $save->{g_chop_optional_groups};

  # Insert widget data: $input_txt
  chomp $save->{input_txt};
  $input_txt->insert('1.0', $save->{input_txt});

  # Insert widget data: Tab 1, stats_tw
  if ( $save->{tab_1} eq 'normal' ) {
    $results_n->tab('1', -state => 'normal');
    update_stats_tw($_) for 0..$#words;
  }

  # Insert results
  if ( $save->{tab_2} eq 'normal' ) {
    $results_n->tab('2', -state => 'normal');
    finish_output();
  }

  # Select tab
  if (exists $save->{tab_selected}) {
    $results_n->select($save->{tab_selected});
  }
}

sub about_lynkeus {
  my @msg_lines = split "\n", <<EOT;
Lynkeus Version $VERSION
This software is Copyright © 2023 by Michael Neidhart.
Diogenes and its modules are Copyright © 1999–2023 by Peter J. Heslin.
This is free software, licensed under:
The GNU General Public License, Version 3, June 2007
EOT

  # window definition
  my $about = $mw->new_toplevel
    (
     -padx => 5,
     -pady => 5,
    );
  $about->g_wm_title($ls{about});
  $about->g_wm_iconphoto('icon');
  my @about_l;
  $about_l[0] = $about->new_ttk__label
    ( -text => $msg_lines[0], -font => [-weight => 'bold'] );
  $about_l[0]->g_grid(-column => 0, -row => 0, -pady => '5 10');  
  my $i;
  for ($i = 1; $i <= $#msg_lines; ++$i) {
    $about_l[$i] = $about->new_ttk__label( -text => $msg_lines[$i] );
    $about_l[$i]->g_grid(-column => 0, -row => $i, -pady => '2 2');
  }
  my $about_b = $about->new_ttk__button
    (-text => $ls{close},
     -command => sub { $about->g_destroy() },
  );
  $about_b->g_grid(-column => 0, -row => ++$i, -pady => '10 5');
  $about->g_bind('<KeyPress>', sub { $about->g_destroy() } );
}

sub help {
}

#------------------------------------------------
# MISCELLANEOUS FUNCTIONS

sub get_context_type {
  for my $i (0..$#context_types_str) {
    return $context_types[$i] if $context_type_str eq $context_types_str[$i];
  }
}

sub get_context_type_str {
  for my $i (0..$#context_types) {
    return $context_types_str[$i] if $context_type eq $context_types[$i];
  }
}

# Taken over from Perseus.pm, lines 62–80
sub beta_to_utf8 {
  my $text = shift;
  my %fake_obj;    # Dreadful hack
  $fake_obj{encoding} = 'UTF-8';

  $text =~ tr/a-z/A-Z/;
  # $text =~ s/_//g; # delete combining macron
  # $text =~ s/\^//g; # delete combining breve
  $text =~ s!_([/\=()]+)!$1_!g;
  $text =~ s!\^([/\=()]+)!$1_!g;
  Diogenes::Base::beta_encoding_to_external(\%fake_obj, \$text);
  # $text =~ s/([\x80-\xff])_/$1\314\204/g; # combining macron
  $text =~ s/_/\314\204/g;
  # $text =~ s/([\x80-\xff])\^/$1\314\206/g; # combining breve
  $text =~ s/\^/\314\204/g;
  # Decode from a 'binary string' to a UTF-8 'text string'
  return Encode::decode('utf-8', $text);
}

sub clear_directory {
  my $path = shift;
  my $errors;
  my $glob = File::Spec->catfile("$path", "*.dat");
  while (my $file = glob("$path* $glob")) {
    next if -d $file;
    unlink($file)
      or ++$errors, warn("Can't remove $file: $!");
  }
}

sub message {
  my $parent = ($_[0] =~ /^\./)
    ? shift
    : $mw;
  my $message = join '', @_;
  Tkx::tk___messageBox
    (
     -parent => $parent,
     -type => 'ok',
     # -icon => 'info',
     -message => $message,
    );
}

sub error {
  my $parent = ($_[0] =~ /^\./)
    ? shift
    : $mw;
  my $message = join '', @_;
  Tkx::tk___messageBox
    (
     -parent => $parent,
     -type => 'ok',
     -icon => 'error',
     -message => $message,
    );
}

sub is_numeric  { return (shift =~ /\D/) ? 0 : 1 }
sub is_integer  { return (shift =~ /[^0-9]/) ? 0 : 1 }
sub numerically { $a <=> $b }

Tkx::MainLoop();
