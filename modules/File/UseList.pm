package File::UseList;

#
# File::UseList
#
# Fuehren einer Liste mit Dateien, auf die zur Zeit zugegriffen wird
# (basiert auf Filing::UseList von Roland Bluethgen <calocybe@web.de>)
#
# Autor:            Patrick Canterino <patshaping@gmx.net>
# Letzte Aenderung: 20.9.2003
#

use strict;

use Carp qw(croak);

our $VERSION = '1.0';

# new()
#
# Konstruktor
#
# Parameter: Hash: listfile => Datei mit der Liste der benutzten Dateien
#                  lockfile => Lock-Datei
#                  timeout  => Lock-Timeout in Sekunden (Standard: 10)
#
# Rueckgabe: File::UseList-Objekt

sub new(%)
{
 my ($class,%args) = @_;

 # Pruefen, ob wir alle Informationen erhalten haben

 croak "Missing path of list file" unless($args{'listfile'});
 croak "Missing path of lockfile"  unless($args{'lockfile'});
 $args{'timeout'} = 10             unless($args{'timeout'});  # Standard-Timeout

 my $self = \%args;
 $self->{'files'} = [];

 return bless($self,$class);
}

# lock()
#
# Datei mit Liste sperren
# (Lock-Datei loeschen)
#
# Parameter: -keine-
#
# Rueckgabe: Status-Code (Boolean)

sub lock
{
 my $self     = shift;
 my $lockfile = $self->{'lockfile'};
 my $timeout  = $self->{'timeout'};

 # Versuche, einmal pro Sekunde die Datei zu loeschen
 # bis das Timeout erreicht ist

 for(my $x=$timeout;$x>=0;$x--)
 {
  unlink($lockfile) and return 1;
  sleep(1);
 }

 # Timeout

 return;
}

# unlock()
#
# Datei mit Liste freigeben
# (Lock-Datei anlegen)
#
# Parameter: -keine-
#
# Rueckgabe: Status-Code (Boolean)

sub unlock
{
 my $self     = shift;
 my $lockfile = $self->{'lockfile'};
 local *LOCKFILE;

 return 1 if(-f $lockfile); # Hmmm...

 open(LOCKFILE,">",$lockfile) or return;
 close(LOCKFILE)              or return;

 return 1;
}

# load()
#
# Liste mit Dateien laden
#
# Parameter: -keine-
#
# Rueckgabe: Status-Code (Boolean)

sub load
{
 my $self = shift;
 my $file = $self->{'listfile'};
 local *FILE;

 # Datei auslesen und zeilenweise aufteilen

 open(FILE,"<".$file) or return;
 read(FILE, my $content, -s $file);
 close(FILE)          or return;

 my @files = split(/\015\012|\012|\015/,$content);

 # Unbrauchbare Zeilen entfernen

 for(my $x=0;$x<@files;$x++)
 {
  if($files[$x] eq "" || $files[$x] =~ /^\s+$/)
  {
   splice(@files,$x,1);
   $x--; # <-- sehr wichtig!
  }
 }

 $self->{'files'} = \@files;
 return 1;
}

# save()
#
# Liste mit Dateien speichern
#
# Parameter: -keine-
#
# Rueckgabe: Status-Code (Boolean)

sub save
{
 my $self  = shift;
 my $file  = $self->{'listfile'};
 my $temp  = $file.".temp";
 my $files = $self->{'files'};
 local *FILE;

 my $data = (@$files) ? join("\n",@$files)."\n" : '';

 open(FILE,">",$temp) or return;
 print FILE $data;
 close(FILE)          or return;

 rename($temp,$file) and return 1;

 # Mist

 return;
}

# add_file()
#
# Datei zur Liste hinzufuegen
#
# Parameter: Datei

sub add_file($)
{
 my ($self,$file) = @_;
 my $files = $self->{'files'};

 # Pruefen, ob die Datei nicht schon in der Liste vorhanden ist

 return if($self->in_use($file));

 push(@$files,$file);
}

# remove_file()
#
# Datei aus der Liste entfernen
#
# Parameter: Datei

sub remove_file($)
{
 my ($self,$file) = @_;
 my $files = $self->{'files'};

 # Pruefen, ob die Datei ueberhaupt in der Liste vorhanden ist

 return if($self->unused($file));

 # Datei entfernen

 for(my $x=0;$x<@$files;$x++)
 {
  if($files->[$x] eq $file)
  {
   splice(@$files,$x,1);
   last;
  }
 }
}

# in_use()
#
# Pruefen, ob eine Datei in der Liste vorhanden ist
#
# Parameter: Zu pruefende Datei
#
# Rueckgabe: Status-Code (Boolean)

sub in_use($)
{
 my ($self,$file) = @_;
 my $files = $self->{'files'};

 foreach(@$files)
 {
  return 1 if($_ eq $file);
 }

 return;
}

# unused()
#
# Pruefen, ob eine Datei nicht in der Liste vorhanden ist
#
# Parameter: Zu pruefende Datei
#
# Rueckgabe: Status-Code (Boolean)

sub unused($)
{
 return not shift->in_use(shift);
}

# it's true, baby ;-)

1;

#
### Ende ###