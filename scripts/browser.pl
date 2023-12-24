#! perl
use v5.14;
use utf8;
use FindBin qw($Bin);
use File::Spec;
use Data::Dumper;
use lib File::Spec->catdir($Bin, '..', 'lib');
use Diogenes::Browser;
use Tkx;

# Global variables
our $browser_column_count = shift || 2;

our $auth   = sprintf "%04d", shift // '0086';
# our $work   = sprintf "%03d",shift // '034';
our $offset = shift // 5160469;

$browser_column_count--;

# SYSTEM-SPECIFIC VARIABLES
our $windowing_system = Tkx::tk_windowingsystem();
Tkx::ttk__style_theme_use('clam') if $windowing_system eq 'x11';

# SCROLLING
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

# FONTS
our $normal_size = 10;
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
#  Tkx::font_configure('TkFixedFont',        -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkMenuFont',         -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkHeadingFont',      -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkIconFont',         -family => 'Gentium', -size => $normal_size);
  Tkx::font_configure('TkCaptionFont',      -family => 'Gentium', -size => $big_size);
  Tkx::font_configure('TkSmallCaptionFont', -family => 'Gentium', -size => $small_size);
  Tkx::font_configure('TkTooltipFont',      -family => 'Gentium', -size => $small_size);
}


# MAIN WINDOW
our $mw = Tkx::widget->new('.');
$mw->g_wm_title('Lynkeus Browser');
my $icon_path = File::Spec->catdir($Bin, '..', 'data', 'icon.png');
Tkx::image_create_photo( "icon", -file => $icon_path);
$mw->g_wm_iconphoto('icon');
Tkx::option_add("*tearOff", 0);

# Resizing
$mw->g_wm_minsize(1000,640);
# $mw->g_wm_resizable(0,0);

# MAIN FRAME
our $mfrm = $mw->new_tk__frame
  (
   -background => 'white'
   # -padding => "12 12 12 12",
  );
# $mfrm->configure(-background => 'white');

$mw->g_grid_columnconfigure(0, -weight => 1);
$mw->g_grid_rowconfigure   (0, -weight => 1);

$mfrm->g_grid (-column => 0, -row => 0, -sticky => "nwes");

$mfrm->g_grid_rowconfigure   (0, -weight => 0);
$mfrm->g_grid_rowconfigure   (1, -weight => 1);

our $backward_bttn = $mfrm->new_ttk__button
  (-text => "←",
   -width => 3,
   -command => \&backward,
  );

our $forward_bttn = $mfrm->new_ttk__button
  (-text => "→",
   -width => 3,
   -command => \&forward,
  );

$backward_bttn->g_grid (-column => 0, -row => 1);
$forward_bttn->g_grid  (-column => $browser_column_count + 2, -row => 1);
$mfrm->g_grid_columnconfigure(0, -weight => 0);
$mfrm->g_grid_columnconfigure($browser_column_count + 2, -weight => 0);

our $header_txt = $mfrm->new_tk__text
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

our @browser_txt;
for my $i (0..$browser_column_count) {
  $mfrm->g_grid_columnconfigure($i + 1, -weight => 1);
  $browser_txt[$i] = $mfrm->new_tk__text
    (
     -width  => 70,
     -height => 30,
     -font   => 'TkTextFont',
     # -padx   => 5,
     # -pady   => 5,
     -wrap   => 'word',
     #  -bg     => 'gray85',
     -borderwidth => 10,
     -relief => 'flat',
     -spacing3 => 2,
     -insertborderwidth => 0,
     -highlightthickness => 0,
    );
  $browser_txt[$i]->g_grid(-column => $i + 1, -row => 1,  -sticky => "nwes");
}


# Increase and decrease fonts
sub set_browser_text_font {
  my $text_font_size = $normal_size;
  return sub {
    my $num = shift;
    my $active = Tkx::focus();
    $text_font_size = ($text_font_size + $num > 5)
      ? $text_font_size + $num
      : 5;
    if ($gentium_availible) {
      for my $txt (@browser_txt) {
	$txt->configure(-font => [-family => 'Gentium', -size => "$text_font_size"]);
      }
    }
    else {
      for my $txt (@browser_txt) {
	$txt->configure(-font => [-size => "$text_font_size"]);
      }
    }
  }
}


# Key Bindings
our $browser_txt_scale = set_browser_text_font();
$mw->g_bind('<Control-plus>',        [\&$browser_txt_scale, '1'] );
$mw->g_bind('<Control-KP_Add>',      [\&$browser_txt_scale, '1'] );
$mw->g_bind('<Control-minus>',       [\&$browser_txt_scale, '-1'] );
$mw->g_bind('<Control-KP_Subtract>', [\&$browser_txt_scale, '-1'] );

$mw->g_bind('<Prior>', sub { backward() for 0..$browser_column_count });
$mw->g_bind('<Next>',  sub { forward()  for 0..$browser_column_count });
$mw->g_bind('<Left>',  \&backward);
$mw->g_bind('<Right>', \&forward);
$mw->g_bind('<Home>',  \&begin);
$mw->g_bind('<End>',   \&end);

$mw->g_bind('<Escape>',   sub{ $mw->g_destroy() });


#############
# LOAD DATA #
#############


my $browser = Diogenes::Browser::Lynkeus->new
  (
   -type => 'tlg',
  );

$auth = $browser->parse_idt($auth);
my $work = $browser->get_work($auth, $offset);

my @result = $browser->seek_passage
  (
   $auth,
   $work,
   # (1, 1, 0)
  );
say $result[0];
# my $start = $browser->get_relative_offset($result[0], $auth, $work);
my $start = $browser->get_relative_offset($offset, $auth, $work);

our @buffers;
our @headers;
our @indices;

# get x and a half page backwards

load_passage($start);


Tkx::MainLoop();


### FUNCTIONS
sub load_passage {
  my $start = shift;
  my $buf;
  my @ind;

  local *STDOUT;
  open STDOUT, '>:raw', \$buf;
  @ind = $browser->browse_half_backward($start, -1);
  say STDERR my $times = ($browser_column_count) / 2;
  for (1..$times) {
    $buf = '';
    open STDOUT, '>:raw', \$buf;
    @ind = $browser->browse_backward(@ind);
  }
  unshift @buffers, \$buf;
  unshift @indices, \@ind;

  browse($browser_column_count);
  insert_contents();
}

sub browse {
  my $count = shift;
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
      @ind = $browser->browse_forward(@{ @indices[-1] });
      return -1 if @ind[1] == -1;
 #     say STDERR for @ind;
      push @buffers, \$buf;
      push @indices, \@ind;
      if ($#buffers > $browser_column_count) {
	shift @buffers; shift @indices;
	say STDERR Dumper(@indices);
      }
    }
    else {
      @ind = $browser->browse_backward(@{ @indices[0] });
      return -1 if $ind[0] == $indices[0][0];
#      say STDERR for @ind;
      unshift @buffers, \$buf;
      unshift @indices, \@ind;
      if ($#buffers > $browser_column_count) {
	pop @buffers; pop @indices;
	say STDERR Dumper(@indices);
      }
    }
  }
}

sub insert_contents {
  for my $i (0..$browser_column_count) {
    $browser_txt[$i]->configure(-state => 'normal');
    open my $str_fh, '<:utf8', $buffers[$i];
    local $/ = "\n\n";
    $headers[$i] = <$str_fh>;

    my $buf = '';
    $buf .= $_ while <$str_fh>;
    # Chop beginning of the following work
    if ( (my $pos = index $buf, '/ / /') != -1) {
      $buf = substr $buf, 0, $pos;
      $buf .= "\n"
    }
    $browser_txt[$i]->delete("1.0", "end");
    $browser_txt[$i]->insert("end", "$buf");
    $browser_txt[$i]->delete("end-1l", "end");
    $browser_txt[$i]->configure(-state => 'disabled');
  }
  $header_txt->configure(-state => 'normal');
  $header_txt->delete("1.0", "end");
  $header_txt->insert("end", $headers[0]);
  $header_txt->delete("end-1l", "end");
  $header_txt->tag_add("header", "1.0", "end");
  $header_txt->configure(-state => 'disabled');
}

sub forward {
  my $r = browse(1);
  unless ($r == -1) {
    $forward_bttn->state("!disabled");
    $backward_bttn->state("!disabled");
    insert_contents();
  }
  else {
    $forward_bttn->state("disabled");
  }
}

sub begin {
  until (browse(-1) == -1) { };
  $backward_bttn->state("disabled");
  $forward_bttn->state("!disabled");
  insert_contents();
}

sub end {
  until (browse(1) == -1) { };
  $forward_bttn->state("disabled");
  $backward_bttn->state("!disabled");
  insert_contents();
}

sub backward {
  my $r = browse(-1);
  unless ($r == -1) {
    $forward_bttn->state("!disabled");
    $backward_bttn->state("!disabled");
    insert_contents();
  }
  else {
    $backward_bttn->state("disabled");
  }
}
