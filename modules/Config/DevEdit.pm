package Config::DevEdit;

#
# Dev-Editor - Module Config::DevEdit
#
# Read and parse the configuration files
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2010-12-24
#
# Copyright (C) 1999-2000 Roland Bluethgen, Frank Schoenmann
# Copyright (C) 2003-2009 Patrick Canterino
# All Rights Reserved.
#
# This file can be distributed and/or modified under the terms of
# of the Artistic License 1.0 (see also the LICENSE file found at
# the top level of the Dev-Editor distribution).
#

use strict;

use vars qw(@EXPORT);
use Carp qw(croak);

use Text::ParseWords;

### Export ###

use base qw(Exporter);

@EXPORT = qw(read_config);

# This variable contains some dependencies for the "disable_commands"
# configuration option.
# The Hash key defines a command, the value is an Array Reference or String
# defining the commands that will also be disabled.

my %disable_dependency = ('beginedit' => 'endedit',
                          'remove' => 'remove_multi',
                          '@write' => ['beginedit','endedit','copy','rename','remove','remove_multi','mkdir','mkfile','upload','chprop']);

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

 # Check if we have to parse the user config file

 if($ENV{'REMOTE_USER'} && $config->{'userconf_file'} && -f $config->{'userconf_file'})
 {
  my $userconf = parse_config($config->{'userconf_file'});

  # Parse aliases (we use references, so we won't get a memory
  # problem so soon...)

  foreach my $user(keys(%$userconf))
  {
   if(my $aliases = $userconf->{$user}->{'aliases'})
   {
    foreach my $alias(parse_line('\s+',0,$aliases))
    {
     $userconf->{$alias} = $userconf->{$user} unless($userconf->{$alias});
    }
   }
  }

  if($userconf->{$ENV{'REMOTE_USER'}})
  {
   # The current HTTP Auth user has got an individual configuration
   # Overwrite the default values

   my $new_conf = $userconf->{$ENV{'REMOTE_USER'}};

   $config->{'fileroot'}         = $new_conf->{'fileroot'}  if($new_conf->{'fileroot'});
   $config->{'httproot'}         = $new_conf->{'httproot'}  if($new_conf->{'httproot'});
   $config->{'startdir'}         = $new_conf->{'startdir'}  if($new_conf->{'startdir'});

   $config->{'forbidden'}        = $new_conf->{'forbidden'} if(defined $new_conf->{'forbidden'});
   $config->{'disable_commands'} = $new_conf->{'disable_commands'} if(defined $new_conf->{'disable_commands'});

   $config->{'hide_dot_files'}   = $new_conf->{'hide_dot_files'} if(defined $new_conf->{'hide_dot_files'});

   $config->{'user_config'}      = 1;
  }
 }

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
 else
 {
  $config->{'forbidden'} = [];
 }

 # Parse list of disabled commands (we need some universal code!)

 if($config->{'disable_commands'})
 {
  my @commands;

  foreach my $command(parse_line('\s+',0,$config->{'disable_commands'}))
  {
   push(@commands,$command) unless(substr($command,0,1) eq '@');

   if(exists($disable_dependency{$command}) && $disable_dependency{$command})
   {
    if(ref($disable_dependency{$command}) eq 'ARRAY')
    {
     push(@commands,@{$disable_dependency{$command}});
    }
    else
    {
     push(@commands,$disable_dependency{$command});
    }
   }
  }

  $config->{'disable_commands'} = \@commands;
 }
 else
 {
  $config->{'disable_commands'} = [];
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
 my $sect;

 foreach my $line(@lines)
 {
  $count++;

  next if($line =~ /^\s*#/);

  if($line =~ /^\s*\[(\S+)\]\s*$/)
  {
   # Switch to new section

   $sect = $1;
  }
  elsif($line =~ /^\s*\S+\s*=.*$/)
  {
   # A normal "key = value" line

   my ($key,$value) = split(/=/,$line,2);

   # Remove whitespaces at the beginning and at the end

   $key   =~ s/^\s+//g;
   $key   =~ s/\s+$//g;
   $value =~ s/^\s+//g;
   $value =~ s/\s+$//g;

   if($sect)
   {
    $config->{$sect} = {} if(ref($config->{$sect}) ne 'HASH');

    croak "Configuration option '$key' of section '$sect' defined twice in line $count of configuration file '$file'" if($config->{$sect}->{$key});

    $config->{$sect}->{$key} = $value;
   }
   else
   {
    croak "Configuration option '$key' defined twice in line $count of configuration file '$file'" if($config->{$key});

    $config->{$key} = $value;
   }
  }
 }

 return $config;
}

# it's true, baby ;-)

1;

#
### End ###