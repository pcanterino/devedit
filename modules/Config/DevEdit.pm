package Config::DevEdit;

#
# Dev-Editor - Module Config::DevEdit
#
# Read and parse the configuration files
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-06-09
#

use strict;

use vars qw(@EXPORT);
use Carp qw(croak);

use Text::ParseWords;

### Export ###

use base qw(Exporter);

@EXPORT = qw(read_config);

# read_config()
#
# Read the configuration files of Dev-Editor
#
# Params: Path to main configuration file
#
# Return: Configuration (Hash Reference)

sub read_config($)
{
 my $file = shift;

 my $config = parse_config($file);

 $config->{'errors'}    = parse_config($config->{'error_file'});
 $config->{'templates'} = parse_config($config->{'template_file'});

 # Parse list of forbidden files

 if($config->{'forbidden'})
 {
  my @files;

  foreach my $file(parse_line('\s+',0,$config->{'forbidden'}))
  {
   $file =~ tr!\\!/!;

   $file =  '/'.$file unless($file =~ m!^/!);
   $file =~ s!/+$!!g;

   push(@files,$file);
  }

  $config->{'forbidden'} = \@files;
 }

 return $config;
}

# parse_config()
#
# Parse a configuration file
#
# Params: Path to configuration file
#
# Return: Configuration (Hash Reference)

sub parse_config($)
{
 my $file = shift;
 local *CF;

 open(CF,'<'.$file) or croak("Open $file: $!");
 read(CF, my $data, -s $file);
 close(CF);

 my @lines  = split(/\015\012|\012|\015/,$data);
 my $config = {};
 my $count  = 0;

 foreach my $line(@lines)
 {
  $count++;

  next if($line =~ /^\s*#/);
  next if($line !~ /^\s*\S+\s*=.*$/);

  my ($key,$value) = split(/=/,$line,2);

  # Remove whitespaces at the beginning and at the end

  $key   =~ s/^\s+//g;
  $key   =~ s/\s+$//g;
  $value =~ s/^\s+//g;
  $value =~ s/\s+$//g;

  croak "Configuration option '$key' defined twice in line $count of configuration file '$file'" if($config->{$key});

  $config->{$key} = $value;
 }

 return $config;
}

# it's true, baby ;-)

1;

#
### End ###