#!C:/Programme/Perl/bin/perl.exe -w

#
# Dev-Editor
#
# Dev-Editor's main program
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 09-22-2003
#

use strict;
use CGI::Carp qw(fatalsToBrowser);

use lib 'modules';

use CGI;
use Command;
use File::UseList;
use Output;
use Tool;

our $VERSION = '0.7';

### Settings ###

our %config = (
               fileroot     => 'D:/Server/WWW/Root',
               httproot     => '/',
               uselist_file => 'uselist',
               lock_file    => 'uselist.lock',
               lock_timeout => '10'
              );

### End Settings ###

# Read the most important form data

my $cgi = new CGI;

my $command = $cgi->param('command') || 'show';
my $file    = $cgi->param('file')    || '/';

# This check has to be performed first, or abs_path() will be confused

if(-e clean_path($config{'fileroot'}."/".$file))
{
 if(my ($physical,$virtual) = check_path($config{'fileroot'},$file))
 {
  # Copied from old Dev-Editor (great idea)

  my %dispatch = ('show'         => \&exec_show,
                  'beginedit'    => \&exec_beginedit,
                  'canceledit'   => \&exec_unlock,
                  'endedit'      => \&exec_endedit,
                  # 'mkdir'        => \&exec_mkdir,
                  # 'mkfile'       => \&exec_mkfile,
                  'workwithfile' => \&exec_workwithfile,
                  # 'copy'         => \&exec_copy,
                  # 'rename'       => \&exec_rename,
                  'remove'       => \&exec_remove,
                  'unlock'       => \&exec_unlock
                 );

  # Create a File::UseList object and load the list

  my $uselist = new File::UseList(listfile => $config{'uselist_file'},
                                  lockfile => $config{'lock_file'},
                                  timeout  => $config{'lock_timeout'});

  $uselist->lock or abort("Locking failed. Try it again in a moment. If the problem persists, ask someone to recreate the lockfile ($config{'lock_file'}).");
  $uselist->load;

  # Create a hash with data submitted by user
  # (the CGI and the File::UseList objects will also be included)

  my %data = (physical     => $physical,
              virtual      => $virtual,
              new_physical => '',
              new_virtual  => '',
              uselist      => $uselist,
              cgi          => $cgi);

  unless($dispatch{$command})
  {
   $uselist->unlock;
   abort("Unknown command: $command");
  }

  my $output = &{$dispatch{$command}}(\%data,\%config); # Execute the command...

  $uselist->unlock; # ... unlock the list with used files...
  print $$output;   # ... and print the output of the command
 }
 else
 {
  abort("Accessing files and directories above the virtual root directory is forbidden.");
 }
}
else
{
 abort("File/directory does not exist.");
}

#
### End ###