#! perl
use v5.14;
use strict;
use warnings;

# use Memory::Usage;
# our $mu = Memory::Usage->new();
# $mu->record('starting work');

use Tkx;
use utf8;

# for.diacritis insensitive comparisons and matches
use Unicode::Collate;
our $Collator = Unicode::Collate->new
  (normalization => undef, level => 1);
use Data::Dumper;
use Encode;

use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir($Bin, '..', 'lib');
use Diogenes::Search;
use Diogenes::Indexed;

binmode STDOUT, ':utf8';
# use open qw( :std :encoding(UTF-8) );

#----------------------------------------------------------------------
# SYSTEM-SPECIFIC VARIABLES
our $windowing_system = Tkx::tk_windowingsystem();

#----------------------------------------------------------------------
our $autoscroll = 1;

# Scaling on Windows is off
# Autoscaling does not work either (tklib is not installee)
if ($^O =~ /win/i) {
  $autoscroll = 0;
  Tkx::tk('scaling', '3')
}

# active autoscroll if tklib is installed
if ($autoscroll){
  Tkx::package_require("autoscroll");
  $autoscroll = 1;
}
# Tkx::i::call("::autoscroll::wrap); # Funktioniert nicht!

#----------------------------------------------------------------------
# TK THEMES

# say Tkx::ttk__style_theme_names();
Tkx::ttk__style_theme_use('clam') if $windowing_system eq 'x11';

# if ($windowing_system eq 'x11') {
#   Tkx::eval("lappend auto_path \"../lib/ttk-Breeze\"");
#   Tkx::eval("package require ttk::theme::Breeze");
#   Tkx::ttk__style_theme_use('Breeze');
# }

#----------------------------------------------------------------------
# FONTS
our $normal_size = 11;
our $small_size  = ($normal_size - 2);
our $big_size    = ($normal_size + 2);
our $gentium_availible;
{
  my $font_families = Tkx::font_families();
  $gentium_availible = 1 if $font_families =~ / Gentium /;
}

if ($gentium_availible) {
  Tkx::font_configure('TkDefaultFont',      -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkTextFont',         -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkFixedFont',        -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkMenuFont',         -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkHeadingFont',      -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkIconFont',         -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkCaptionFont',      -family => 'Gentium', -size => $big_size);
  Tkx::font_configure('TkSmallCaptionFont', -family => 'Gentium', -size => $small_size);
  Tkx::font_configure('TkTooltipFont',      -family => 'Gentium', -size => $small_size);
}

#----------------------------------------------------------------------
# Configuration Variables (to be read in form a file!)
# Search Types
our $st_lemma       = 0;
our $st_synonyma    = 0;
our $st_continentia = 0;
our $si_corpus      = 'TLG';

# Language
our $gui_lang = 'deu';
our $default_threshold_percent = 30;

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

  $ls{search_type} = 'Search type';
  $ls{verbatim}    = 'verbatim';
  $ls{lemma}       = 'lemma';

  $ls{synonyma}    = 'verba synonyma';
  $ls{continentia} = 'verba continentia';
  $ls{search_in}   = 'Search in';

  $ls{lemmata}        = 'Lemmata';
  $ls{single_results} = 'Hits for single words';
  $ls{result}         = 'Parallel passages';
  $ls{statistics}     = 'Statistics';
  $ls{cancel}         = 'Cancel';
  $ls{ok}             = 'Ok';
  $ls{total}          = 'Total';

  $ls{form}           = 'Form';
  $ls{single_forms}   = 'Forms';
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

  $ls{error_empty}  = 'Please enter a text!';
  $ls{error_unknown_st} = 'Unknown corpus:';
  $ls{error_implemented_PHI} = 'PHI not yet implemented!';
  $ls{error_implemented} = 'Not yet implemented!';
  $ls{error_select}  = 'Please select a search term!';
  $ls{error_results}  = 'No results!';
  $ls{error_lemma}  = 'No results for';

  if    ($gui_lang eq 'eng') {  }
  else {
    eval {
      open my $locale_fh, '<:utf8',
	File::Spec->catfile
	  ($Bin, '..', 'data', 'locale', "$gui_lang")
	  or die
	  "I was not able to load the language file $gui_lang: $!\n";

      while (<$locale_fh>) {
	# m/^\s*-?(\w+)\s+=?\s*([^"\n]*)\s*/;
	# my $key = $1;
	# my $value = $2;
 	chomp;
	s/#.*//;
	s/^\s+//;
	s/\s+$//;
	next unless length;

	my ($key, $value) = split(/\s*=\s*/, $_, 2);
	$ls{$key} = $value if exists $ls{$key};
      }
    };

    if ($@) {
      say $@;
      $gui_lang = 'eng';
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
our $interrupt = 0;
our $input_str;
our @words = ();
our @undo_words = ();
our $max_undo_words = 10;
our %results = ();
our %output = ();

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
our $progress_word;
our $progress_total;
our $progress_w_bar;
our $progress_t_bar;
our $progress_w_l;
our $progress_t_l;

our @selected_str;
our @selected_num;
our $weight;

$si_corpus = 'Aristoteles';

# Lemma search specific
our @selected_headword = ();
our @selected_lemma = ();
our $stem_min = 1;
our $max_alt = 50;
our $chop_optional_groups = 0;

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
# $mw->g_wm_resizable(0,0);

#----------------------------------------------------------------------
# MENU BARS
#----------------------------------------------------------------------

Tkx::option_add("*tearOff", 0);
our $menu = $mw->new_menu;
$mw->configure(-menu => $menu);

our $search_m = $menu->new_menu;
our $pref_m   = $menu->new_menu;
our $help_m   = $menu->new_menu;

$menu->add_cascade
  (
   -menu      => $search_m,
   -label     => $ls{search},
   -underline => 0,
  );
$menu->add_cascade
  (
   -menu      => $pref_m,
   -label     => $ls{pref},
   -underline => 0,
  );
$menu->add_cascade
  (
   -menu      => $help_m,
   -label     => $ls{help},
   -underline => 0,
  );

$search_m->add_command
  (
   -label => $ls{new},
   -underline => 0,
   -command => sub {   }
  );
$search_m->add_command
  (
   -label => $ls{save},
   -underline => 0,
   -command => sub {   }
  );
$search_m->add_command
  (
   -label => $ls{load},
   -underline => 0,
   -command => sub {   }
  );
$search_m->add_command
  (
   -label => $ls{quit},
   -underline => 0,
   -command => sub { $mw->g_destroy }
  );

our $lang_m = $pref_m->new_menu;
$pref_m->add_cascade
  (
   -menu => $lang_m,
   -label => $ls{lang},
  );
$lang_m->add_radiobutton
  (
   -label => 'Deutsch',
   -underline => 0,
   -variable => \$gui_lang,
   -value => 'deu',
   -command => \&update_lang,
  );
$lang_m->add_radiobutton
  (
   -label => 'English',
   -underline => 0,
   -variable => \$gui_lang,
   -value => 'eng',
   -command => \&update_lang,
  );

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
   # -font   => 'TkTextFont',
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
   -variable => \$st_lemma,
   -value    => 0,
   );

our $st_rbt_lem = $input_bttn_frm->new_ttk__radiobutton
  (
   -text     => $ls{lemma},
   -variable => \$st_lemma,
   -value    => 1,
   );

our $st_cbt_syn = $input_bttn_frm->new_ttk__checkbutton
  (
   -text => $ls{synonyma},
   -command => sub {   },
   -variable => \$st_synonyma,
  );

our $st_cbt_cnt = $input_bttn_frm->new_ttk__checkbutton
  (
   -text => $ls{continentia},
   -command => sub {   },
   -variable => \$st_continentia,
   );

# Source select and start button
our $si_l = $input_bttn_frm->new_ttk__label
  (
   -text => uc( $ls{search_in} ),
#   -padding => '0 0 10 0',
  );
our $si_cbb = $input_bttn_frm->new_ttk__combobox
  (
   -textvariable => \$si_corpus,
   -values => [
	       'TLG',
	       'PHI',
	       'TLG+PHI',
	       'Aristoteles',
	       'Eigenes Corpus...',
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
   # -font   => 'TkTextFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   #  -bg     => 'gray85',
   -border => 0,
   -state => 'disabled',
   -spacing3 => 2,
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

our (%separators);

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
    if ($gentium_availible) {
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
if ($gentium_availible) {
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
# THE MAIN SUBROUTINES
#------------------------------------------------


# $st_rbt_vbt->state('disabled');
# $st_rbt_lem->state('disabled');
$st_cbt_syn->state('disabled');
$st_cbt_cnt->state('disabled');

#------------------------------------------------
# PART 1: PROCESSING THE INPUT TEXT
#------------------------------------------------

#------------------------------------------------
# STEP 1: Set up variables and widgets

sub begin_search {
  ## Chop off trailing newline
  #  if 
  #  $input_txt->delete('end linestart');
  
  # Empty search data
  $results_txt->delete('1.0', 'end');
  $results_n->tab('2', -state => 'hidden');
  $lemmata_cvs->g_destroy() if $lemmata_cvs;
  # We need to clear also the other global variables connected with Tab 0
  undef @lemmata_bttn;
  undef $lemmata_continue_bttn;
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



  $input_bttn->configure
    (
     -text => $ls{cancel},
     -command => sub { $interrupt = 1 },
    );
  $input_bttn_text = 'cancel';
  $input_txt->configure(-state => "disabled");

  Tkx::after(5, \&get_input)
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
  my %seen = ();
  @input_words =
    # Remove duplicates, but remember the times we have seen this word
    grep { ! $seen{ $_ }++ }
    # Remove interpunctation, make all lowercase
    map
    {
      $_ =~ s/^[(<\[{]//;
      $_ =~ s/[\.··\?\])>},;·]$//;
      lc $_;
    }
    @input_words;

  # Process words, populate @words array
 WORD: for my $word (@input_words) {
    # Remove words found on the backlist
    for (@blacklist) {
      # Make comparison diacritics insensitive
      my $w = $word =~ tr#/\\=()|\*##rd;
      if ( $Collator->eq($w, $_) ) {
	# Get indices of the word and make it grey
	my @positions = get_positions($word, @input_lines);
	while (@positions) {
	  my $line  = shift @positions;
	  my $begin = shift @positions;
	  my $end   = shift @positions;
	  $input_txt->tag_add("blacklist", "$line.$begin", "$line.$end");
	}
	next WORD;
      }
    }

    # Get indices of the words in the original string
    my @positions = get_positions($word, @input_lines);
    die
      "I expected $seen{ $word } hits for $word but found only "
      . ( @positions / 3 ) . " hit for $word"
      if ($seen{ $word } * 3 != @positions);

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
  make_progress_bars();
  # make_stats_tw();
  # clear stats_tw
  my @stats_tw_items = $stats_tw->children('');
  $stats_tw->delete("@stats_tw_items");

  Tkx::after( 10, [\&mark_word, 0] );
}

#------------------------------------------------
# Step 2c: Helper functions
sub get_positions {
  my ($word, @input_lines) = @_;
  my @positions;
  # $word = lc Diogenes::UnicodeInput->unicode_greek_to_beta($word);
  my $l = 0;
  for my $line (@input_lines) {
    $l++;
    # $line = lc Diogenes::UnicodeInput->unicode_greek_to_beta($line);
    while ($line =~ m/(?:^|\s+|[\[(<])(\Q$word\E)(?:$|\s+|[\])>.,··;?!])/gi) {
      push @positions, $l;
      push @positions, $-[1];
      push @positions, $+[1];
    }
  }
  return @positions;
}

sub make_progress_bars {
  my $total = @words;
  $progress_frm = $input_frm->new_ttk__frame
      (
       -padding => "0 38 0 10",
      );
  $progress_frm->g_grid(-column => 0, -row => 2, -sticky => "we");
  $progress_frm->g_grid_columnconfigure(0, -weight => 1);
  $progress_frm->g_grid_columnconfigure(1, -weight => 1);

  $progress_t_l = $progress_frm->new_ttk__label
      (
       -text => uc( "$ls{total}: 0/$total" ),
       #  -padding => '0 0 10 0',
      );
  $progress_t_bar = $progress_frm->new_ttk__progressbar
    (
     -orient => 'horizontal',
     -length => 280,
     -maximum => ( $total ),
     -mode => 'determinate'
    );

  $progress_t_l  ->g_grid(-column => 0, -row => 1, -sticky => "w", -padx => [4, 10]);
  $progress_t_bar->g_grid(-column => 1, -row => 1, -sticky => "e");

  # if ($st_lemma or $st_synonyma or $st_continentia) {
  #   $progress_w_l = $progress_frm->new_ttk__label
  #     (
  #      -text => uc( "$ls{total}: 0/$total" ),
  #      #  -padding => '0 0 10 0',
  #     );
  #   $progress_w_bar = $progress_frm->new_ttk__progressbar
  #     (
  #      -orient => 'horizontal',
  #      -length => 200,
  #      -mode => 'determinate'
  #     );
  #   $progress_w_l->g_grid  (-column => 0, -row => 0, -sticky => "w", -padx => [4, 10]);
  #   $progress_w_bar->g_grid(-column => 1, -row => 0, -sticky => "e");
  # }
}

sub update_progress_bars {
  (my $number = shift)++;
  my $total = @words;
  $progress_t_bar->configure(-value => $number);
  $progress_t_l  ->configure(-text => "$ls{total}: $number/$total"),
}

sub update_stats_tw {
  my $index = shift;
  my $word = $words[$index]{word};
  my $hits = $words[$index]{hits};
  my $weight = 1;
   $stats_tw->insert
     (
      "",
      "end",
      -id     => "$word",
      -open   => "false",
      -text   => "$word",
      -values => "$hits $weight",
 #     -style  => "Row.Treeview",
     );
}

#------------------------------------------------
# STEP 3: Process each word in turn

sub mark_word {
  end_search() and return if $interrupt;

  # unmark all words in $input_txt
  $input_txt->tag_remove("searching", '1.0', 'end');

  # get the index, return if we got past the last valid index
  say my $index = shift;
  Tkx::after( 5, \&end_search ) and return if $index > $#words;

  # mark words currently searched for in $input_txt
  my @positions  = @{ $words[$index]{positions} };
  my $times_seen = $words[$index]{times_seen};
  while ($times_seen--) {
    my $line  = shift @positions;
    my $begin = shift @positions;
    my $end   = shift @positions;
    $input_txt->tag_add("searching", "$line.$begin", "$line.$end");
  }

  # update progress bars
  update_progress_bars($index);

  Tkx::after( 5, [\&tlg_search, $index] );
}

# TODO: In order to get more control over the search and give the user
# more feedback with a status bar, we should alter this function so
# that the searches are not only sequential for the input words, but
# also for all tlg files. We can do so by selecting only one author at
# a time with select_authors(), get the output and matches, then call
# again select_authors() on the same Diogenes::Search object. For this
# to work, we have to manually construct a list of the selected authors:
#
# Whole tlg:
#    my @ordered_nums = @{ $query->{tlg_ordered_authnums} };
#    for @ordered_nums {
#      $query->select_authors(author_nums = [$_]);
#      $query_>pgrep
#    }
#
# For searches restricted by author numbers, we have to order the list:
#    my @nums = shift;
#    my %nums = map { $_,1 } @nums;
#    my @ordered = @{ $query->{tlg_ordered_authnums} };
#    my @ordered_nums = ();
#    for (@ordered) {
#        push @ordered_nums, $_ if exists $nums{$_} ;
#     }
#
# But beware: Some categories (as, e.g., "genre", do work based
# searches not yet supported by Lynkeus!

sub tlg_search {
  end_search() and return if $interrupt;
  my $index = shift;

  # With beta code input, there is an issue that some patterns (eg
  # hdonh) do not respect word boundaries: This works only reliably,
  # if we give it at least one accent to use (breathings are
  # insignificant for this). It seems best to use unicode, either
  # strict with all accents, or loose without any (breathings, again,
  # do not interfere with this).

  # -> beta without diacritics: Blazing fast, unreliable
  # beta with diacritics: Fast and reliable
  # unicode without diacritics: Slow, reliable
  # unicode with diacritics: Fast, unreliable

  my @patterns;
  my $query;
  if ($st_lemma) {
    @patterns = @{ $words[$index]{forms} };
      for my $pattern (@patterns) {
	# make pattern diacritics insensitive
	# already done in make_lemma_patterns!
	# $pattern  =~ tr#/\\=()|\*##d;
	# only whole words should be matched
	$pattern = " $pattern ";
	say "#$pattern#";
      }

    # do the search, redirect STDOUT TO $out_string
    $query = Diogenes::Search->new
      (
       -type => 'tlg',
       -pattern_list => \@patterns,
      );
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

    # do the search, redirect STDOUT TO $out_string
    $query = Diogenes::Search->new
      (
       -type => 'tlg',
       -pattern => "$pattern",
      );
  }

  # restrict search to the selected value
  for ($si_corpus) {
    if (/^TLG$/) {
      $query->select_authors();
    }
    elsif (/PHI$/) {
      error($ls{error_implemented_PHI});
      end_search();
      edit_search();
      return;
    }
    elsif (/^Aristoteles$/) {
      $query->select_authors
	(-author_nums => [86]);
    }
    # List of author numbers
    elsif (/^\d{1,4}(?:,\s*\d{1,4})*$/) {
      my @nums;
      push @nums, $& while /\d{1,4}/g;
      $query->select_authors
	(-author_nums => \@nums);
    }
    # error
    else {
      error($ls{error_unknown_st}, $_);
      end_search();
      edit_search();
      return;
    }
  }

  my $result;
  {
    local *STDOUT;
    open STDOUT, '>:raw', \$result;
    $query->do_search;
    delete $query->{buf};	# Clean the buffer hold in memory by the object
  }

  # print_out(\$result);

  # save results in @words
  $words[$index]{result} = \$result;
  $words[$index]{hits} = $query->get_hits();
  # We don't save the whole Diogenes object anymore, but only the
  # parts we are interested in
  # $words[$index]{query} = $query;
  $words[$index]{seen_all} = $query->{seen_all};
  $words[$index]{match_start_all} = $query->{match_start_all};

  update_stats_tw($index);

  Tkx::after( 5, [\&mark_word, ++$index] );
}

#------------------------------------------------
# STEP 4: CLEANUP

sub end_search {
  $interrupt = 0;
  $input_txt->tag_remove("searching", '1.0', 'end');

  $progress_frm->g_destroy() if $progress_frm;

  $input_bttn->configure
    (
     -text => $ls{edit},
     -command => \&edit_search,
    );
  $input_bttn_text = 'edit';
  $mw->g_bind("<Control-Return>", sub { $results_bttn->invoke() } );
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
  $input_txt->configure(-state => "normal");
  $input_txt->g_focus();
  $mw->g_bind("<Control-Return>", sub { $input_bttn->invoke() } );
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
      push @selected_num, $index if $str eq $words[$index]{word};
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

  # delete words from $words
  my @indices = ();

 INDEX: for my $index (0..$#words)  {
    for my $num (@selected_num) {
      next INDEX if $num == $index;
    }
    push @indices, $index;
  }

  @words = @words[@indices];
  say $words[$_]{word} for (0..$#words);

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
  # Get context values
  return unless $context;
  $context_type = get_context_type();
  error(get_context_type_str(), ": $ls{error_implemented}") and return
    if grep $context_type eq $_, qw(clause sentence line);

  # Get the entered weight for each word
  for my $i (0..$#words) {
    my $word = $words[$i]{word};
    $words[$i]{weight} = $stats_tw->set ( "$word", "weight");
  }

  # Prepare $results_txt, delete old separators
  $separators{$results_txt} = [];
  $results_txt->configure(-state => 'normal');
  $results_txt->delete('1.0', 'end');
  $results_n->tab('2', -state => 'normal');
  $results_n->select('2');

  # Populate the %results data structure
  %results = ();
  for my $word (@words) {
    # reconstruct Diogenes' query hash for each word
    # my $query_ref = $word->{query};
    # my @tlg_numbers = keys %{ $query_ref->{seen_all} };
    my @tlg_numbers = keys %{ $word->{seen_all} };

    # get the single matches
    for my $tlg_number (@tlg_numbers) {
      # next unless defined $query_ref->{seen_all}{$tlg_number};
      # my @match_starts = sort numerically @{ $query_ref->{match_start_all}{$tlg_number} };
      # my @matches      = sort numerically @{ $query_ref->{seen_all}{$tlg_number} };
      next unless defined $word->{seen_all}{$tlg_number};
      my @match_starts = sort numerically @{ $word->{match_start_all}{$tlg_number} };
      my @matches      = sort numerically @{ $word->{seen_all}{$tlg_number} };

      # make for each hit a hash, pass the needed values from @words,
      # add the data for $match_start
      for my $i (0..$#matches) {
	# $results{$tlg_number}{$hit} = $word;
	$results{$tlg_number}{$matches[$i]}{word}   = $word->{word};
	$results{$tlg_number}{$matches[$i]}{hits}   = $word->{hits};
	$results{$tlg_number}{$matches[$i]}{result} = $word->{result};
	$results{$tlg_number}{$matches[$i]}{weight} = $word->{weight};
	$results{$tlg_number}{$matches[$i]}{match_start} = $match_starts[$i];
	# $results{$tlg_number}{$matches[$i]}{query}  = $word->{query};
      }
    }
  }

  get_context_matches();
  output();
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
}

sub output {
  %output = ();
  my $output_string = '';
  my @pattern_list;
  if ($st_lemma) {
    @pattern_list = map " $words[$_]{word} " , (0..$#words);
    for (0..$#words) {
      push @pattern_list, @{ $words[$_]{forms} };
    }
    say @pattern_list = map { " $_ " } @pattern_list;
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

  my $buf;
  # TODO: Get a better configuration of the Diogenes::Search object
  my $printer = Diogenes::Search->new
    (
     -type => 'tlg',
     -pattern_list => [ @pattern_list ],
     # -max_context => 1000,
     -context => 'paragraph',
    );
  $printer->{buf} = \$buf;
  $printer->{current_lang} = 'g';

  for my $tlg_number (keys %results) {

    # open the desired file, load it into $buf;
    my $inp;
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
      # TODO: buggy in lemma search!
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
	# Here is the BUG!
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
  }

  # sort and concatenate results
  # Get the keys of $results (that is, the tlg file names) into
  # chronological order
  my @ordered_nums = @{ $printer->{tlg_ordered_authnums} };
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

  my @info;
  for my $tlg_number (@ordered_result_keys) {
    for my $match (0..$#{ $output{$tlg_number} }) {
      $output_string .= $output{$tlg_number}[$match]{output};
      push @info, $output{$tlg_number}[$match]{info};
      # print_results( \$output_string, $results_txt, \@info );
    }
  }

  if ($output_string) {
    print_results( \$output_string, $results_txt, \@info );
  }
  else {
    $results_n->tab('2', -state => 'hidden');
    error($ls{error_results});
  }

  $results_txt->configure(-state => 'disabled');
}

sub print_results {
  my $output_string = shift;
  my $output_txt = shift;
  my $info_ref = shift;
  my @info = ref $info_ref
    ? @{ $info_ref }
    : ();

  Tkx::update();
  my %highlight;
  my @header_lines;
  my @info_lines;

  # Print $output_string to $output_txt, one line at a time
  open my $str_fh, '<:utf8', $output_string;
  my $i = $output_txt->index('end');
  $i =~ s/(\d+).*/$1/;
  $i--;

  # Here, we want to do several thing:
  # - replace the ugly ~~~ with horizontal lines
  # - replace the -><- markers with the Tk tag 'marked'
  # - replace ###INFO### with $info, remember the lines for markup
  # - remember the lines of the header fpr markup

  # Initialisation of the separators and the header switch
  my $header = 1;
  my $separator_count = 0;
  $separators{$output_txt} = [];
  my $separator_width = ( $output_txt->g_winfo_width() - 20);
  while (<$str_fh>) {
    my $line = $_;
    my (@highlight_starts, @highlight_ends);

    # Create separator lines
    if ($line =~ /^~~~.*~~~$/){
      $header = 1;
      my $j = $i -1;

      $separators{$output_txt}[$separator_count] = $output_txt->new_tk__canvas
	(-width => $separator_width, -height => 3);
      $output_txt->window_create
	("$j.0", -window => $separators{$output_txt}[$separator_count]);
      $separators{$output_txt}[$separator_count]->create_line
	(0,0,10000,0,
	 -fill => 'black',
	 -width => 3
	);
      $separator_count++;
      next;
    }

    if (@info and $line =~ /^###INFO###$/) {
      $line = shift @info;
      $line .= "\n";
      push @info_lines, $i;
      $header = 0;
    }

    if ($header) {
      push @header_lines, $i;
      $header = 0 if $line =~ /^$/;
    }

    # As we want to highlight the matches with the highlight tag,
    # we now have to delete the -> <- marks and save the positions;
    my $first = 1;
    while ($line =~ s/->|<-//) {
      my $match = $&;
      my $pos = $-[0];
      if ($first) {
	if ($match eq '->') {
	  push @highlight_starts, "$pos";
	  push @highlight_ends, "end";
	}
	if ($match eq '<-') {
	  push @highlight_starts, "0";
	  push @highlight_ends, "$pos";
	}
	$first = 0;
      }
      else {
	if ($match eq '->') {
	  push @highlight_starts, "$pos";
	  push @highlight_ends, "end";
	}
	if ($match eq '<-') {
	  pop @highlight_ends;
	  push @highlight_ends, "$pos";
	}
      }
    }

    $highlight{$i}{begin} = \@highlight_starts;
    $highlight{$i}{end} =   \@highlight_ends;
    $output_txt->insert("$i.0", "$line");
    ++$i;
  }
  close $str_fh;

  # Highlight the results
  for my $i (sort numerically keys %highlight) {
    my @highlight_starts = @{ $highlight{$i}{begin}  };
    my @highlight_ends = @{ $highlight{$i}{end}  };

    for my $index (0..$#highlight_starts){
      my $begin = $highlight_starts[$index];
      my $end = $highlight_ends[$index];
      $output_txt->tag_add("matched", "$i.$begin", "$i.$end");
    }
  }

  for my $i (@header_lines){
    my $j = $i + 1;
    $output_txt->tag_add("header", "$i.0", "$j.0");
  }

  for my $i (@info_lines){
    my $j = $i + 1;
    $output_txt->tag_add("info", "$i.0", "$j.0");
  }

  # clear first and last newlines
  # $i -= 3;
  # $output_txt->delete("$i.0", "end");
  # $output_txt->delete("1.0", "2.0");
  # pop  @{ $separators{$output_txt} };
}

sub update_separator_width {
  for my $txt (keys %separators){
    Tkx::update();
    my $output_width = ( Tkx::winfo_width($txt) - 20);
    for my $separator ( @{ $separators{$txt} } ){
      $separator->configure(-width => $output_width) if $separator;
    }
  }
}

#------------------------------------------------
# PART 3:  LEMMA SEARCH
#------------------------------------------------

# STEP 1: Setup the lemmata tab
sub setup_lemma_search {
  end_search() and return if $interrupt;

  # clear the global variables
  @selected_headword = ();
  @selected_lemma    = ();
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

  # Get analyses, error.message and next @word if analysis fails
  my %analyses = get_lemma($word);
  unless (keys %analyses) {
    error( $ls{error_lemma}, " $word!" );
    if ($i == $#words) { Tkx::after( 10, [\&finish_setup_lemma, ($i+1) ] ); }
    else               { Tkx::after( 10, [\&setup_lemma, $i ]); }
    return;
  }

  $words[$i]{analyses} = \%analyses;

  # Headword combobox
  my @headwords = sort keys %analyses;
  $selected_headword[$i] = $headwords[0];
  $headword_cbb_callback[$i] = make_headwords_callback($i);
  $headword_cbb[$i] = $lemmata_frm->new_ttk__combobox
    (
     -textvariable => \$selected_headword[$i],
     -values => \@headwords,
     -state => 'readonly'
    );
  $headword_cbb[$i]->g_bind
    ("<<ComboboxSelected>>",
     sub { $headword_cbb_callback[$i]($selected_headword[$i]) });
  unless ($#headwords){   # disable the widget if there is no choice
    $headword_cbb[$i]->state('disabled');
  }

  # Lemmata combobox
  my @lemmata = sort keys %{ $analyses{$headwords[0]} };
  $selected_lemma[$i] = $lemmata[0];
  $lemmata_cbb[$i] = $lemmata_frm->new_ttk__combobox
    (
     -textvariable => \$selected_lemma[$i],
     -values => \@lemmata,
     -state => 'readonly'
    );
  $lemmata_cbb[$i]->g_bind
    ("<<ComboboxSelected>>", sub { $lemmata_cbb[$i]->selection_clear });
  unless ($#lemmata){		# disable the widget if there is no choice
    $lemmata_cbb[$i]->state('disabled');
  }

  # Show single forms button
  $lemmata_bttn_callback[$i] = make_show_bttn_callback($i);
  $lemmata_bttn[$i] = $lemmata_frm->new_ttk__button
    (
     -text => "$ls{single_forms}...",
     -command => \&{ $lemmata_bttn_callback[$i] },
     );

  # Geometry
  my $row = $i + 1;
  $headword_cbb[$i]->g_grid(-column => 0, -row => $row, -sticky => 'ew', -padx => '10 4', -pady => '0 5');
  $lemmata_cbb[$i] ->g_grid(-column => 1, -row => $row, -sticky => 'ew', -padx => '4 4', -pady => '0 5');
  $lemmata_bttn[$i]->g_grid(-column => 2, -row => $row, -sticky => 'ew', -padx => '4 10', -pady => '0 5');

  say $selected_headword[$i];
  say $selected_lemma[$i];
  say $analyses{$selected_headword[$i]}{$selected_lemma[$i]}{number};

  if ($i == $#words) { Tkx::after( 10, [\&finish_setup_lemma, ($i+1) ] ); }
  else               { Tkx::after( 10, [\&setup_lemma, $i ]); }
}

sub make_show_bttn_callback {
  my $i = shift;
  return sub { show_single_forms($i) }
}
sub show_single_forms {
  my $i = shift;
  my $word = $words[$i]{word};
  my @forms = map { beta_to_utf8($_) } get_forms($i);

  $words[$i]{undo_forms_blacklist} = $words[$i]{forms_blacklist} if $words[$i]{forms_blacklist};

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
  unless ( $words[$i]{forms_blacklist} ) {
    $words[$i]{forms_blacklist}[$_] = 0 for 0..$#forms;
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
       -variable => \$words[$i]{forms_blacklist}[$index],
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
       $_ = 0 for @{ $words[$i]{forms_blacklist} }
     },
    );
  my $forms_select_none = $forms_bttn_frm->new_ttk__button
    (-text => $ls{select_none},
     -command => sub {
       $_ = 1 for @{ $words[$i]{forms_blacklist} }
       },
    );
  my $forms_cancel_bttn = $forms_bttn_frm->new_ttk__button
    (-text => $ls{cancel},
     -command => sub {
       if ($words[$i]{undo_forms_blacklist}) {
	 $words[$i]{forms_blacklist} = $words[$i]{undo_forms_blacklist};
	 delete $words[$i]{undo_forms_blacklist}
       }
       else { delete $words[$i]{forms_blacklist} }
     },
    );
  my $forms_ok_bttn = $forms_bttn_frm->new_ttk__button
    (-text => $ls{ok},
     -command => sub {
       if ($words[$i]{undo_forms_blacklist}) {
	 delete $words[$i]{undo_forms_blacklist}
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

sub make_headwords_callback {
  my $i = shift;
  # my $headword = shift;
  # my $headword = $$headword_ref;
  return sub {
    my $headword = shift;
    headwords_callback($i, $headword);
  }
}
sub headwords_callback {
  say my $i = shift;
  say my $headword = shift;
  say my @lemmata = sort keys %{ $words[$i]{analyses}{$headword} };
  $selected_lemma[$i] = $lemmata[0];
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
  # Progress bars

  Tkx::after( 10, [\&retrieve_forms, 0] );
}

sub retrieve_forms {
  my $i = shift;
  Tkx::after( 10, \&finish_lemma_setup ) and return if $i > $#words;

  # get the forms, remove the forms found on the word's forms_blacklist
  my @forms = get_forms($i);
  my @indices = grep { ! $words[$i]{forms_blacklist}[$_] } 0..$#forms;
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

  my $headword = $selected_headword[$i];
  my $lemma = $selected_lemma[$i];
  my $number = $words[$i]{analyses}{$headword}{$lemma}{number};

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
    my %hash = %{ $hashref };
    my @keys = keys %hash;
    my $optional = 0;
    my @subpatterns;

    return '' if (@keys == 1 and $keys[0] eq '0');

    for my $key (@keys){
      if ($key eq '0') { $optional = 1 }
      else {
	my $subpattern = hash_to_pattern(\%{ $hash{$key}  });
	push @subpatterns, "$key$subpattern";
      }
    }
    my $pattern = join '|', @subpatterns;
    $pattern = "($pattern)";
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
  say for @pattern_list;
  return @pattern_list;
}

#------------------------------------------------
# STEP 5: Finish the setup

sub finish_lemma_setup {
  $results_n->tab('0', -state => 'hidden');
  $results_n->tab('1', -state => 'normal');
  $results_n->select('1');
  Tkx::after( 10, \&finish_setup );
}


#------------------------------------------------
# PART 4: SUBWINDOWING FUNCTIONS
#------------------------------------------------
# VIEW SINGLE RESULTS
sub view_single_results {
  # get currently selected entrie(s)
  # say my @selected_strings = split /\s+/, $stats_tw->selection();
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

  my $viewer_txt = $viewer->new_tk__text
  (
   -width  => 62,
   -height => 20,
   # -font   => 'TkTextFont',
   -padx   => 5,
   -pady   => 5,
   -wrap   => 'word',
   #  -bg     => 'gray85',
   -border => 0,
   -spacing3 => 2,
  );
  my $viewer_scroll = $viewer->new_ttk__scrollbar
  (
   -orient => 'vertical',
   -command => [$viewer_txt, 'yview']
  );
  $viewer_txt->configure(-yscrollcommand => [$viewer_scroll, 'set']);
  $viewer_scroll->g___autoscroll__autoscroll() if $autoscroll;

  my $viewer_bttn = $viewer->new_ttk__button
    (-text => $ls{close},
     -command => sub {
       delete $separators{$viewer_txt}; $viewer->g_destroy()
     },
    );
  $viewer->g_wm_protocol
    (
     "WM_DELETE_WINDOW" => sub {
       delete $separators{$viewer_txt}; $viewer->g_destroy()
     },
    );

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

  # insert the contents
  my $output_str = '';
  for my $index (@selected_num) {
    $output_str .= ${$words[$index]{result}}
  }
  print_results(\$output_str, $viewer_txt);
  $viewer_txt->configure(-state => 'disabled');
}

# BLACKLIST EDITOR

# PREFERENCES

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

sub update_lang {
  gui_lang();
  $menu->entryconfigure(0, -label => $ls{search});
  $menu->entryconfigure(1, -label => $ls{pref});
  $menu->entryconfigure(2, -label => $ls{help});

  $search_m->entryconfigure(0, -label => $ls{new});
  $search_m->entryconfigure(1, -label => $ls{save});
  $search_m->entryconfigure(2, -label => $ls{load});
  $search_m->entryconfigure(3, -label => $ls{quit});

  $pref_m->entryconfigure(0, -label => $ls{lang});

  $st_l->configure(-text => $ls{search_type});
  $st_rbt_vbt->configure(-text => $ls{verbatim});
  $st_rbt_lem->configure(-text => $ls{lemma});
  $st_cbt_syn->configure(-text => $ls{synonyma});
  $st_cbt_cnt->configure(-text => $ls{continentia});

  $si_l->configure(-text => $ls{search_in});
  $input_bttn->configure(-text => $ls{$input_bttn_text});

  if (@lemmata_bttn){
    $lemmata_bttn[$_]->configure(-text => $ls{single_forms}) for (0..$#lemmata_bttn)
  }
  $lemmata_continue_bttn->configure(-text => $ls{continue}) if $lemmata_continue_bttn;

  $results_n->tab('0', -text => $ls{lemmata});
  $results_n->tab('1', -text => $ls{statistics});
  $results_n->tab('2', -text => $ls{result});

  $stats_show_bttn->configure(-text => $ls{view})   if $stats_show_bttn;
  $results_bttn->configure   (-text => $ls{result}) if $results_bttn;

  $stats_wrd_l->configure   (-text => uc( $ls{search_term} ))  if $stats_wrd_l;
  $stats_add_bttn->configure(-text => $ls{add})                if $stats_add_bttn;
  $stats_edit_bttn->configure (-text => $ls{edit})             if $stats_edit_bttn;
  $stats_rm_bttn->configure (-text => $ls{remove})             if $stats_rm_bttn;

  $stats_weight_l->configure(-text => uc( $ls{weight})) if $stats_weight_l;

  $stats_context_l->configure(-text => uc( $ls{context})) if $stats_context_l;
  $stats_threshold_l->configure(-text => uc( $ls{threshold})) if $stats_threshold_l;

  $stats_tw->heading("#0", -text => $ls{search_term}, -anchor => "w")
    if $stats_tw;
  $stats_tw->heading("hits", -text => $ls{numberofhits}, -anchor => "w")
    if $stats_tw;
  $stats_tw->heading("weight", -text => $ls{weight}, -anchor => "w")
    if $stats_tw;

  @context_types_str_sing = split /\s+/, $ls{contexts};
  @context_types_str_plur = split /\s+/, $ls{Contexts};
  @context_types_str = ($context > 1)
    ? @context_types_str_plur
    : @context_types_str_sing;
  $context_type_str = get_context_type_str();
  $stats_context_cbb->configure(-values => \@context_types_str)
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
};

sub error {
  my $message = join '', @_;
  Tkx::tk___messageBox
      (
       -type => 'ok',
       -icon => 'error',
       -message => $message,
      );
}

sub is_numeric  { return (shift =~ /\D/) ? 0 : 1 }
sub numerically { $a <=> $b }

# File operations
# $filename = Tkx::tk___getOpenFile();
# $filename = Tkx::tk___getSaveFile();
# $dirname = Tkx::tk___chooseDirectory();

# Message Boxes
# Tkx::tk___messageBox(-message => "Have a good day");
# Tkx::tk___messageBox(-type => "yesno",
# 	    -message => "Are you sure you want to install SuperVirus?",
# 	    -icon => "question", -title => "Install");

Tkx::MainLoop();
