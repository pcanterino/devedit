package Template;

#
# Template (Version 2.0)
#
# Klasse zum Parsen von Templates
#
# Autor:            Patrick Canterino <patrick@patshaping.de>
# Letzte Aenderung: 31.7.2006
#

use strict;

use Carp qw(croak);
use File::Spec;

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
 my $self  = {file => '', template => '', original => '', vars => {}, defined_vars => [], loop_vars => {}};
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
# Einlesen einer Vorlagendatei und {INCLUDE}-Anweisungen ggf. verarbeiten
# (Text wird an bereits vorhandenen Text angehaengt)
#
# Parameter: 1. Datei zum Einlesen
#            2. Status-Code (Boolean):
#               true  => {INCLUDE}-Anweisungen nicht verarbeiten
#               false => {INCLUDE}-Anweisungen verarbeiten (Standard)
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub read_file($;$)
{
 my ($self,$file,$not_include) = @_;
 local *FILE;

 $self->{'file'} = $file;

 open(FILE,'<'.$file) or croak "Open $file: $!";
 read(FILE, my $content, -s $file);
 close(FILE) or croak "Closing $file: $!";

 $self->add_text($content);
 $self->save_state;

 $self->parse_includes unless($not_include);
}

# set_var()
#
# Wert einer Variable setzen
#
# Parameter: 1. Name der Variable
#            2. Wert, den die Variable erhalten soll
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub set_var($$)
{
 my ($self,$var,$content) = @_;
 $self->{'vars'}->{$var} = $content;
}

# get_var()
#
# Wert einer Variable zurueckgeben
#
# Parameter: (optional) Variablenname
#
# Rueckgabe: Wert der Variable;
#            wenn die Variable nicht existiert, false;
#            wenn kein Variablenname angegeben wurde, wird ein
#            Array mit den Variablennamen zurueckgegeben

sub get_var(;$)
{
 my ($self,$var) = @_;

 if(defined $var)
 {
  if($self->{'vars'}->{$var})
  {
   return $self->{'vars'}->{$var};
  }
  else
  {
   return undef;
  }
 }
 else
 {
  return keys %{$self->{'vars'}};
 }
}

# set_loop_data()
#
# Daten fuer eine Schleife setzen
#
# Parameter: 1. Name der Schleife
#            2. Array-Referenz mit den Hash-Referenzen mit
#               den Variablen fuer die Schleifendurchgaenge
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub set_loop_data($$)
{
 my ($self,$loop,$data) = @_;
 $self->{'loop_vars'}->{$loop} = $data;
}

# add_loop_data()
#
# Daten fuer einen Schleifendurchgang hinzufuegen
#
# Parameter: 1. Name der Schleife
#            2. Hash-Referenz mit den Variablen fuer den
#               Schleifendurchgang
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub add_loop_data($$)
{
 my ($self,$loop,$data) = @_;

 if($self->{'loop_vars'}->{$loop} && ref($self->{'loop_vars'}->{$loop}) eq 'ARRAY')
 {
  push(@{$self->{'loop_vars'}->{$loop}},$data);
 }
 else
 {
  $self->{'loop_vars'}->{$loop} = [$data];
 }
}

# parse()
#
# In der Template definierte Variablen auslesen, Variablen
# ersetzen, {IF}- und {TRIM}-Bloecke parsen
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse
{
 my $self = shift;

 # Zuerst die Schleifen parsen

 if($self->{'loop_vars'} && (my @loops = keys(%{$self->{'loop_vars'}})))
 {
  foreach my $loop(@loops)
  {
   $self->parse_loop($loop);
  }
 }

 # Normale Variablen durchgehen

 foreach my $var($self->get_var)
 {
  my $val = $self->get_var($var);

  $self->parse_if_block($var,$val);

  if(ref($val) eq 'ARRAY')
  {
   $self->fillin_array($var,$val);
  }
  else
  {
   $self->fillin($var,$val);
  }
 }

 # Jetzt dasselbe mit denen, die direkt in der Template-Datei definiert
 # sind, machen. Ich weiss, dass das eine ziemlich unsaubere Loesung ist,
 # aber es funktioniert

 $self->get_defined_vars;

 foreach my $var(@{$self->{'defined_vars'}})
 {
  my $val = $self->get_var($var);

  $self->parse_if_block($var,$val);
  $self->fillin($var,$val);
 }

 # {TRIM}-Bloecke entfernen

 $self->parse_trim_blocks;
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

 $text = '' unless defined $text; # Um Fehler zu vermeiden

 my $template = $self->get_template;
 $template    = str_replace('{'.$var.'}',$text,$template);

 $self->set_template($template);
}

# fillin_array()
#
# Variable durch Array ersetzen
#
# Parameter: 1. Variable zum Ersetzen
#            2. Array-Referenz, durch die die Variable ersetzt werden soll
#            3. Zeichenkette, mit der das Array verbunden werden soll
#               (Standard: '')
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub fillin_array($$;$)
{
 my ($self,$var,$array,$glue) = @_;
 $glue = '' unless defined $glue;

 $self->fillin($var,join($glue,@$array));
}

# to_file()
#
# Template in Datei schreiben
#
# Parameter: Datei-Handle
#
# Rueckgabe: Status-Code (Boolean)

sub to_file($)
{
 my ($self,$handle) = @_;
 return print $handle $self->get_template;
}

# reset()
#
# Den gesicherten Stand des Template-Textes sichern
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub reset
{
 my $self = shift;
 $self->{'template'} = $self->{'original'};
}

# save_state()
#
# Aktuellen Stand des Template-Textes sichern
# (alte Sicherung wird ueberschrieben)
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub save_state
{
 my $self = shift;
 $self->{'original'} = $self->{'template'};
}

# parse_loop()
#
# Eine Schleife parsen
#
# Parameter: Name der Schleife
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_loop($)
{
 my ($self,$name) = @_;

 my $template = $self->get_template;
 return if(index($template,'{LOOP '.$name.'}') == -1);

 my $offset   = 0;
 my $name_len = length($name);

 while((my $begin = index($template,'{LOOP '.$name.'}',$offset)) != -1)
 {
  if((my $end = index($template,'{ENDLOOP}',$begin+6+$name_len)) != -1)
  {
   my $block   = substr($template,$begin,$end+9-$begin);
   my $content = substr($block,$name_len+7,-9);

   my $parsed_block = '';

   for(my $x=0;$x<scalar @{$self->{'loop_vars'}->{$name}};$x++)
   {
    my $loop_data = $self->{'loop_vars'}->{$name}->[$x];
    my @loop_vars = keys(%$loop_data);

    my $ctpl = new Template;
    $ctpl->set_template($content);

    foreach my $loop_var(@loop_vars)
    {
     $ctpl->set_var($name.'.'.$loop_var,$loop_data->{$loop_var});
    }

    $ctpl->parse;
    $parsed_block .= $ctpl->get_template;

    undef($ctpl);
   }

   $template = str_replace($block,$parsed_block,$template);
   $offset   = $begin+length($parsed_block);
  }
  else
  {
   last;
  }
 }

 $self->set_template($template);
}

# get_defined_vars()
#
# In der Template-Datei definierte Variablen auslesen
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub get_defined_vars
{
 my $self = shift;

 my $template = $self->get_template;
 return if(index($template,'{DEFINE ') == -1);

 my $offset = 0;

 while(index($template,'{DEFINE ',$offset) != -1)
 {
  my $begin = index($template,'{DEFINE ',$offset)+8;
  $offset   = $begin;

  my $name    = '';
  my $content = '';

  my $var_open     = 0;
  my $name_found   = 0;
  my $define_block = 0;

  for(my $x=$begin;$x<length($template);$x++)
  {
   if(substr($template,$x,1) eq "\012" || substr($template,$x,1) eq "\015")
   {
    # Wenn in einem {DEFINE}-Block ein Zeilenumbruch gefunden wird,
    # brechen wir mit dem Parsen des Blockes ab

    last;
   }

   if($var_open == 1)
   {
    if(substr($template,$x,1) eq '"')
    {
     # Der Inhalt der Variable ist hier zu Ende

     $var_open = 0;

     if(substr($template,$x+1,1) eq '}')
     {
      # Hier ist der Block zu Ende

      if(not defined $self->get_var($name))
      {
       # Die Variable wird nur gesetzt, wenn sie nicht bereits gesetzt ist

       $self->set_var($name,$content);
       push(@{$self->{'defined_vars'}},$name);
      }

      # {DEFINE}-Block entfernen

      my $pre  = substr($template,0,$begin-8);
      my $post = substr($template,$x+2);

      $template = $pre.$post;

      # Fertig!

      $offset = length($pre);
      last;
     }
    }
    elsif(substr($template,$x,1) eq '\\')
    {
     # Ein Backslash wurde gefunden, er dient zum Escapen von Zeichen

     if(substr($template,$x+1,1) eq 'n')
     {
      # "\n" in Zeilenumbrueche umwandeln

      $content .= "\n";
     }
     else
     {
      $content .= substr($template,$x+1,1);
     }

     $x++;
    }
    else
    {
     $content .= substr($template,$x,1);
    }
   }
   else
   {
    if($name_found == 1)
    {
     if($var_open == 0)
     {
      if(substr($template,$x,1) eq '"')
      {
       $var_open = 1;
      }
      else
      {
       last;
      }
     }
    }
    else
    {
     # Variablennamen auslesen

     if(substr($template,$x,1) eq '}' && $name ne '')
     {
      # Wir haben einen {DEFINE}-Block

      $name_found   = 1;
      $define_block = 1;

      # Alles ab hier sollte mit dem Teil verbunden werden, der das
      # {DEFINE} in einer Zeile verarbeitet

      # Der Parser fuer {DEFINE}-Bloecke ist nicht rekursiv, was auch
      # nicht noetig sein sollte

      if((my $end = index($template,'{ENDDEFINE}',$x)) != -1)
      {
       $x++;

       $content = substr($template,$x,$end-$x);

       if(not defined $self->get_var($name))
       {
        # Die Variable wird nur gesetzt, wenn sie nicht bereits gesetzt ist

        $self->set_var($name,$content);
        push(@{$self->{'defined_vars'}},$name);
       }

       my $pre  = substr($template,0,$begin-8);
       my $post = substr($template,$end+11);

       $template = $pre.$post;

       # Fertig!

       $offset = length($pre);
       last;
      }
      else
      {
       last;
      }
     }
     elsif(substr($template,$x,1) ne ' ')
     {
      $name .= substr($template,$x,1);
     }
     elsif(substr($template,$x,1) ne '')
     {
      $name_found = 1;
     }
     else
     {
      last;
     }
    }
   }
  }
 }

 $self->set_template($template);
}

# parse_if_block()
#
# IF-Bloecke verarbeiten
#
# Parameter: 1. Name des IF-Blocks (das, was nach dem IF steht)
#            2. Status-Code (true  => Inhalt anzeigen
#                            false => Inhalt nicht anzeigen
#            3. true  => Verneinten Block nicht parsen
#               false => Verneinten Block parsen (Standard)
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_if_block($$;$)
{
 my ($self,$name,$state,$no_negate) = @_;
 my $template                       = $self->get_template;

 my $count = 0;

 while(index($template,'{IF '.$name.'}') >= 0)
 {
  # Das alles hier ist nicht wirklich elegant geloest...
  # ... aber solange es funktioniert... ;-)

  $count++;

  my $start    = index($template,'{IF '.$name.'}');
  my $tpl_tmp  = substr($template,$start);
  my @splitted = explode('{ENDIF}',$tpl_tmp);

  my $block = ''; # Kompletter bedingter Block
  my $ifs   = 0;  # IF-Zaehler (wird fuer jedes IF erhoeht und fuer jedes ENDIF erniedrigt)

  # {IF}

  for(my $x=0;$x<@splitted;$x++)
  {
   croak 'Nesting error found while parsing IF block "'.$name.'" nr. '.$count.' in template file "'.$self->{'file'}.'"' if($x == $#splitted);

   $ifs += substr_count($splitted[$x],'{IF '); # Zum Zaehler jedes Vorkommen von IF hinzuzaehlen
   $ifs--;                                     # Zaehler um 1 erniedrigen
   $block .= $splitted[$x].'{ENDIF}';          # Daten zum Block hinzufuegen

   if($ifs == 0)
   {
    # Zaehler wieder 0, also haben wir das Ende des IF-Blocks gefunden :-))

    last;
   }
  }

  my $if_block = substr($block,length($name)+5,-7); # Alles zwischen {IF} und {ENDIF}

  # {ELSE}

  my $else_block = ''; # Alles ab {ELSE}
     $ifs        = 0;  # IF-Zaehler

  @splitted = explode('{ELSE}',$if_block);

  for(my $x=0;$x<@splitted;$x++)
  {
   $ifs += substr_count($splitted[$x],'{IF ');    # Zum Zaehler jedes Vorkommen von IF hinzuzaehlen
   $ifs -= substr_count($splitted[$x],'{ENDIF}'); # Vom Zaehler jedes Vorkommen von ENDIF abziehen

   if($ifs == 0)
   {
    # Zaehler 0, also haben wir das Ende des IF-Abschnitts gefunden

    # Aus dem Rest den ELSE-Block zusammenbauen

    for(my $y=$x+1;$y<@splitted;$y++)
    {
     $else_block .= '{ELSE}'.$splitted[$y];
    }

    if($else_block)
    {
     $if_block   = substr($if_block,0,length($if_block)-length($else_block));
     $else_block = (length($else_block) > 6) ? substr($else_block,6) : '';    # Ansonsten gibt es Fehler
    }

    last;
   }
  }

  my $replacement = ($state) ? $if_block : $else_block;

  $template = str_replace($block,$replacement,$template);
 }

 $self->set_template($template);

 # Evtl. verneinte Form parsen

 unless($no_negate)
 {
  $self->parse_if_block('!'.$name,not($state),1);
 }
}

# parse_trim_blocks()
#
# {TRIM}-Bloecke parsen
#
# Dieser Parser ist nicht rekursiv, was auch nicht
# noetig sein sollte.
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_trim_blocks
{
 my $self = shift;

 my $template = $self->get_template;
 return if(index($template,'{TRIM}') == -1);

 my $offset = 0;

 while((my $begin = index($template,'{TRIM}')) >= 0)
 {
  if((my $end = index($template,'{ENDTRIM}',$begin+6)) >= 0)
  {
   my $block   = substr($template,$begin,$end+9-$begin);
   my $content = substr($block,6,-9);

   my $trimmed = $content;
   $trimmed    =~ s/^\s+//s;
   $trimmed    =~ s/\s+$//s;

   $template   = str_replace($block,$content,$template);

   $offset     = $begin+length($trimmed);
  }
  else
  {
   last;
  }
 }

 $self->set_template($template);
}

# parse_condtag()
#
# Bedingungstags in einem Vorlagentext verarbeiten
#
# Parameter: 1. Tagname
#            2. Status-Code (true  => Tag-Inhalt anzeigen
#                            false => Tag-Inhalt nicht anzeigen
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_condtag($$)
{
 my ($self,$condtag,$state) = @_;

 my $template = $self->get_template;

 while(index($template,'<'.$condtag.'>') >= 0)
 {
  my $start = index($template,'<'.$condtag.'>');                                # Beginn des Blocks
  my $end   = index($template,'</'.$condtag.'>')+length($condtag)+3;            # Ende des Blocks

  my $extract = substr($template,$start,$end-$start);                           # Kompletten Bedingungsblock extrahieren...

  my $replacement = ($state) ? substr($extract,length($condtag)+2,0-length($condtag)-3) : '';

  $template = str_replace($extract,$replacement,$template);                     # Block durch neue Daten ersetzen
 }
 $self->set_template($template);
}

# parse_includes()
#
# {INCLUDE}-Anweisungen verarbeiten
#
# Parameter: -nichts-
#
# Rueckgabe: -nichts- (Template-Objekt wird modifiziert)

sub parse_includes
{
 my $self = shift;

 my $template = $self->get_template;
 return if(index($template,'{INCLUDE ') == -1);

 my $offset = 0;

 my $y = 0;

 while((my $begin = index($template,'{INCLUDE ',$offset)) != -1)
 {
  $y++;

  my $start = $begin+9;
  $offset   = $start;
  my $long  = 0;

  if(substr($template,$start,1) eq '"')
  {
   $long = 1;
   $start++;
  }

  my $file = '';
  my $skip = 0;

  for(my $x=$start;$x<length($template);$x++)
  {
   my $c = substr($template,$x,1);

   if($c eq "\012" && $c eq "\015")
   {
    $skip = 1;
    last;
   }
   elsif($long == 0 && $c eq ' ')
   {
    $skip = 1;
    last;
   }
   elsif($long == 1 && $c eq '"')
   {
    $skip = 1 if(substr($template,$x+1,1) ne '}');
    last;
   }
   elsif($long == 0 && $c eq '}')
   {
    last;
   }
   else
   {
    $file .= $c;
   }
  }

  next if($skip == 1);

  if($file ne '')
  {
   my $filepath = $file;

   unless(File::Spec->file_name_is_absolute($file))
   {
    my $dir   = (File::Spec->splitpath($self->{'file'}))[1];
    $dir      = '.' unless($dir);
    $filepath = File::Spec->catfile($dir,$file);
   }

   if(-f $filepath)
   {
    my $inc = new Template;
    $inc->read_file($filepath);

    my $end = ($long == 1)
            ? $start + length($file) + 2
            : $start + length($file) + 1;

    my $pre  = substr($template,0,$begin);
    my $post = substr($template,$end);

    $template = $pre.$inc->get_template.$post;
    $offset   = length($pre)+length($inc->get_template);

    undef($inc);
   }
  }
 }

 $self->set_template($template);
}

# ==================
#  Private Funktion
# ==================

# explode()
#
# Eine Zeichenkette ohne regulaere Ausdruecke auftrennen
# (split() hat einen Bug, deswegen verwende ich es nicht)
#
# Parameter: 1. Trennzeichenkette
#            2. Zeichenkette, die aufgetrennt werden soll
#            3. Maximale Zahl von Teilen
#
# Rueckgabe: Aufgetrennte Zeichenkette (Array)

sub explode($$;$)
{
 my ($separator,$string,$limit) = @_;
 my @splitted;

 my $x       = 1;
 my $offset  = 0;
 my $sep_len = length($separator);

 while((my $pos = index($string,$separator,$offset)) >= 0 && (!$limit || $x < $limit))
 {
  my $part = substr($string,$offset,$pos-$offset);
  push(@splitted,$part);

  $offset = $pos+$sep_len;

  $x++;
 }

 push(@splitted,substr($string,$offset,length($string)-$offset));

 return @splitted;
}

# str_replace()
#
# Zeichenkette durch andere ersetzen
#
# Parameter: 1. Zu ersetzender Text
#            2. Ersetzender Text
#            3. Zeichenkette, in der ersetzt werden soll
#
# Rueckgabe: Bearbeitete Zeichenkette (String)

sub str_replace($$$)
{
 my ($search,$replace,$subject) = @_;
 $search = quotemeta($search);

 $subject =~ s/$search/$replace/gs;

 return $subject;
}

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

# it's true, baby ;-)

1;

#
### Ende ###