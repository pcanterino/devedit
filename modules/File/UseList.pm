package File::UseList;

#
# File::UseList 1.2
#
# Run a list with files that are currently in use
# (bases on Filing::UseList by Roland Bluethgen <calocybe@web.de>)
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2003-11-21
#

use strict;

use Carp qw(croak);

# new()
#
# Constructor
#
# Params: Hash: listfile => File with list of files in use
#               lockfile => Lock file (Default: List file + .lock)
#               timeout  => Lock timeout in seconds (Default: 10)
#
# Return: File::UseList object (Blessed Reference)

sub new(%)
{
 my ($class,%args) = @_;

 # Check if we got all the necessary information

 croak "Missing path to list file"             unless($args{'listfile'});
 $args{'lockfile'} = $args{'listfile'}.".lock" unless($args{'lockfile'}); # Default filename of lock file
 $args{'timeout'}  = 10                        unless($args{'timeout'});  # Default timeout

 # Add some other information

 $args{'files'}  = [];
 $args{'locked'} = 0;

 return bless(\%args,$class);
}

# lock()
#
# Lock list with files
# (delete lock file)
#
# Params: -nothing-
#
# Return: Status code (Boolean)

sub lock
{
 my $self     = shift;
 my $lockfile = $self->{'lockfile'};
 my $timeout  = $self->{'timeout'};

 return 1 if($self->{'locked'});

 # Try to delete the lock file one time per second
 # until the timeout is reached

 for(my $x=$timeout;$x>=0;$x--)
 {
  if(unlink($lockfile))
  {
   $self->{'locked'} = 1;
   return 1;
  }

  sleep(1);
 }

 # Timeout

 return;
}

# unlock()
#
# Unlock list with files, but only if _we_ locked it
# (create lock file)
#
# Params: -nothing-
#
# Return: Status code (Boolean)

sub unlock
{
 my $self     = shift;
 my $lockfile = $self->{'lockfile'};
 local *LOCKFILE;

 if($self->{'locked'})
 {
  open(LOCKFILE,">$lockfile") or return;
  close(LOCKFILE)             or return;

  $self->{'locked'} = 0;
  return 1;
 }

 # The list wasn't lock by us or it isn't locked at all

 return;
}

# load()
#
# Load the list with files from the list file
#
# Params: -nothing-
#
# Return: Status code (Boolean)

sub load
{
 my $self = shift;
 my $file = $self->{'listfile'};
 local *FILE;

 # Read out the file and split the content line-per-line

 open(FILE,"<$file") or return;
 read(FILE, my $content, -s $file);
 close(FILE)         or return;

 my @files = split(/\015\012|\012|\015/,$content);

 # Remove useless lines

 for(my $x=0;$x<@files;$x++)
 {
  if($files[$x] eq "" || $files[$x] =~ /^\s+$/)
  {
   splice(@files,$x,1);
   $x--; # <-- very important!
  }
 }

 $self->{'files'} = \@files;
 return 1;
}

# save()
#
# Write the list with files back to the list file
#
# Params: -nothing-
#
# Return: Status code (Boolean)

sub save
{
 my $self  = shift;
 my $file  = $self->{'listfile'};
 my $temp  = $file.".temp";
 my $files = $self->{'files'};
 local *FILE;

 my $data = (@$files) ? join("\n",@$files) : '';

 open(FILE,">$temp") or return;
 print FILE $data    or do { close(FILE); return };
 close(FILE)         or return;

 rename($temp,$file) or return;

 return 1;
}

# add_file()
#
# Add a file to the list
#
# Params: File
#
# Return: Status code (Boolean)

sub add_file($)
{
 my ($self,$file) = @_;
 my $files = $self->{'files'};

 # Check if the file is already in the list

 return if($self->in_use($file));

 push(@$files,$file);
 return 1;
}

# remove_file()
#
# Remove a file from the list
#
# Params: File
#
# Return: Status code (Boolean)

sub remove_file($)
{
 my ($self,$file) = @_;
 my $files = $self->{'files'};

 # Check if the file is really in the list

 return if($self->unused($file));

 # Remove the file from the list

 for(my $x=0;$x<@$files;$x++)
 {
  if($files->[$x] eq $file)
  {
   splice(@$files,$x,1);
   return 1;
  }
 }
}

# in_use()
#
# Check if a file is in the list
#
# Params: File to check
#
# Return: Status code (Boolean)

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
# Check if a file is not in the list
#
# Params: File to check
#
# Return: Status code (Boolean)

sub unused($)
{
 return not shift->in_use(shift);
}

# it's true, baby ;-)

1;

#
### End ###