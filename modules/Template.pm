package Template;

#
# Template (Version 1.2a)
#
# Klasse zum Parsen von Templates
#
# Autor:            Patrick Canterino <patshaping@gmx.net>
# Letzte Aenderung: 12.9.2003
#

use strict;

use Carp qw(croak);

# new()
#
# Konstruktor
#
# Parameter: -keine-
#
# Rueckgabe: Template-Objekt

sub new
{
 my $class = shift;
 my $self  = {template => ''};
 return bless($self,$class);
}

# get_template()
#
# Kompletten Vorlagentext zurueckgeben
#
# Parameter: -keine-
#
# Rueckgabe: Kompletter Vorlagentext (String)

sub get_template
{
 return shift->{'template'};
}

# set_template()
#
# Kompletten Vorlagentext aendern
#
# Parameter: Vorlagentext
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub set_template($)
{
 # Geht nur so...

 my ($self,$template) = @_;
 $self->{'template'}  = $template;
}

# add_text()
#
# Vorlagentext ans Template-Objekt anhaengen
#
# Parameter: Vorlagentext
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub add_text($)
{
 my ($self,$text) = @_;
 $self->set_template($self->get_template.$text);
}

# read_file()
#
# Einlesen einer Vorlagendatei
# (Inhalt wird an bereits vorhandenen Text angehaengt)
#
# Parameter: Datei zum Einlesen
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub read_file($)
{
 my ($self,$tfile) = @_;
 local *FILE;

 open(FILE,"<$tfile") or croak "Open $tfile: $!";
 read(FILE, my $content, -s $tfile);
 close(FILE) or croak "Closing $tfile: $!";

 $self->add_text($content);
}

# fillin()
#
# Variablen durch Text ersetzen
#
# Parameter: 1. Variable zum Ersetzen
#            2. Text, durch den die Variable ersetzt werden soll
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub fillin($$)
{
 my ($self,$var,$text) = @_;

 $var  = quotemeta($var);
 $text = "" unless defined $text; # Um Fehler zu vermeiden

 my $template = $self->get_template;
 $template    =~ s/\{$var\}/$text/g;

 $self->set_template($template);
}

# fillin_array()
#
# Variable durch Array ersetzen
#
# Parameter: 1. Variable zum Ersetzen
#            2. Array-Referenz, durch die die Variable ersetzt werden soll
#            3. Zeichenkette, mit der das Array verbunden werden soll
#               (Standard: "")
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub fillin_array($$;$)
{
 my ($self,$var,$array,$glue) = @_;
 $glue = '' unless defined $glue;

 $self->fillin($var,join($glue,@$array));
}

# parse_if_block()
#
# IF-Bloecke verarbeiten
#
# Parameter: 1. Name des IF-Blocks (das, was nach dem IF steht)
#            2. Statuscode (true  => Inhalt anzeigen
#                           false => Inhalt nicht anzeigen
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_if_block($$)
{
 my ($self,$name,$state) = @_;
 my $template            = $self->get_template;

 while(index($template,"{IF ".$name."}") >= 0)
 {
  # Das alles hier ist nicht wirklich elegant geloest...
  # ... aber solange es funktioniert... ;-)

  my $start    = index($template,"{IF ".$name."}");
  my $tpl_tmp  = substr($template,$start);
  my @splitted = split(/\{ENDIF\}/,$tpl_tmp);

  my $block = ""; # Kompletter bedingter Block
  my $ifs   = 0;  # IF-Zaehler (wird fuer jedes IF erhoeht und fuer jedes ENDIF erniedrigt)

  # {IF}

  for(my $x=0;$x<@splitted;$x++)
  {
   $ifs += substr_count($splitted[$x],"{IF"); # Zum Zaehler jedes Vorkommen von IF hinzuzaehlen
   $ifs--;                                    # Zaehler um 1 erniedrigen
   $block .= $splitted[$x]."{ENDIF}";         # Daten zum Block hinzufuegen

   if($ifs == 0)
   {
    # Zaehler wieder 0, also haben wir das Ende des IF-Blocks gefunden :-))

    last;
   }
  }

  my $if_block = substr($block,length($name)+5,-7); # Alles zwischen {IF} und {ENDIF}

  # {ELSE}

  my $else_block = ""; # Alles ab {ELSE}
     $ifs        = 0;  # IF-Zaehler

  @splitted = split(/\{ELSE\}/,$if_block);

  for(my $x=0;$x<@splitted;$x++)
  {
   $ifs += substr_count($splitted[$x],"{IF");     # Zum Zaehler jedes Vorkommen von IF hinzuzaehlen
   $ifs -= substr_count($splitted[$x],"{ENDIF}"); # Vom Zaehler jedes Vorkommen von ENDIF abziehen

   if($ifs == 0)
   {
    # Zaehler 0, also haben wir das Ende des IF-Abschnitts gefunden

    # Aus dem Rest den ELSE-Block zusammenbauen

    for(my $y=$x+1;$y<@splitted;$y++)
    {
     $else_block .= "{ELSE}".$splitted[$y];
    }

    if($else_block)
    {
     $if_block   = substr($if_block,0,length($if_block)-length($else_block));
     $else_block = (length($else_block) > 6) ? substr($else_block,6) : "";    # Ansonsten gibt es Fehler
    }

    last;
   }
  }

  my $replacement = ($state) ? $if_block : $else_block;

  my $qmblock = quotemeta($block);

  $template =~ s/$qmblock/$replacement/;
 }

 $self->set_template($template);
}

# parse_condtag()
#
# Bedingungstags in einem Vorlagentext verarbeiten
#
# Parameter: 1. Tagname
#            2. Statuscode (true  => Tag-Inhalt anzeigen
#                           false => Tag-Inhalt nicht anzeigen
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_condtag($$)
{
 my ($self,$condtag,$state) = @_;

 my $template = $self->get_template;

 while(index($template,"<$condtag>") >= 0)
 {
  my $start = index($template,"<$condtag>");                                # Beginn des Blocks
  my $end   = index($template,"</$condtag>")+length($condtag)+3;            # Ende des Blocks

  my $extract = substr($template,$start,$end-$start);                       # Kompletten Bedingungsblock extrahieren...

  my $replacement = ($state) ? substr($extract,length($condtag)+2,0-length($condtag)-3) : "";

  $extract = quotemeta($extract);

  $template =~ s/$extract/$replacement/g;                                   # Block durch neue Daten ersetzen
 }
 $self->set_template($template);
}

# ==================
#  Private Funktion
# ==================

# substr_count()
#
# Zaehlt, wie oft ein String in einem String vorkommt
# (Emulation der PHP-Funktion substr_count())
#
# Parameter: 1. Zu durchsuchender String
#            2. Zu suchender String
#
# Rueckgabe: Anzahl der Vorkommnisse (Integer)

sub substr_count($$)
{
 my ($haystack,$needle) = @_;
 my $qmneedle = quotemeta($needle);

 my $count = 0;

 $count++ while($haystack =~ /$qmneedle/g);

 return $count;
}

# ==================
#  Alias-Funktionen
# ==================

sub addtext($)
{
 shift->add_text(shift);
}

sub as_string
{
 return shift->get_template;
}

sub condtag($$)
{
 shift->parse_condtag(@_);
}

sub readin($)
{
 shift->read_file(shift);
}

# it's true, baby ;-)

1;

#
### Ende ###