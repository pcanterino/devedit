package Tool;

#
# Dev-Editor - Module Tool
#
# Some shared sub routines
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 10-03-2003
#

use strict;

use vars qw(@EXPORT);

use Cwd qw(abs_path);
use File::Basename;
use File::Spec;

### Export ###

use base qw(Exporter);

@EXPORT = qw(check_path
             clean_path
             file_name
             upper_path);

# check_path()
#
# Check, if a virtual path is above a virtual root directory
# (currently no check if the path exists - check otherwise!)
#
# Params: 1. Virtual root directory
#         2. Virtual path to check
#
# Return: Array with the physical and the cleaned virtual path;
#         false, if the submitted path is above the root directory

sub check_path($$)
{
 my ($root,$path) = @_;

 # Clean root path

 $root = abs_path($root);
 $root = File::Spec->canonpath($root);

 $path =~ s!^/{1}!!;
 $path = $root."/".$path;

 unless(-d $path)
 {
  # The path points to a file
  # We have to extract the directory name and create the absolute path

  my @pathinfo = fileparse($path);

  # This is only to avoid errors

  my $basename = $pathinfo[0] || '';
  my $dir      = $pathinfo[1] || '';
  my $ext      = $pathinfo[2] || '';

  $dir = abs_path($dir);

  $path = $dir."/".$basename.$ext;
 }
 else
 {
  $path = abs_path($path);
 }

 $path = File::Spec->canonpath($path);

 # Check if the path is above the root directory

 return if(index($path,$root) == -1);

 # Create short path name

 my $short_path = substr($path,length($root));
 $short_path =~ tr!\\!\/!;
 $short_path = "/".$short_path unless($short_path =~ m!^/!);
 $short_path = $short_path."/" if($short_path !~ m!/$! && -d $path);

 return ($path,$short_path);
}

# clean_path()
#
# Clean up a path logically and replace backslashes with
# normal slashes
#
# Params: Path
#
# Return: Cleaned path

sub clean_path($)
{
 my $path =  shift;
 $path    =  File::Spec->canonpath($path);
 $path    =~ tr!\\!/!;

 return $path;
}

# file_name()
#
# Returns the last path of a filename
#
# Params: Path
#
# Return: Last part of the path

sub file_name($)
{
 my $path =  shift;
 $path    =~ tr!\\!/!;

 unless($path eq "/")
 {
  $path = substr($path,0,-1) if($path =~ m!/$!);
  $path = substr($path,rindex($path,"/")+1);
 }

 return $path;
}

# upper_path()
#
# Truncate a path in one of the following ways:
#
# - If the path points to a directory, the upper directory
#   will be returned.
# - If the path points to a file, the directory containing
#   the file will be returned.
#
# Params: Path
#
# Return: Truncated path

sub upper_path($)
{
 my $path =  shift;
 $path    =~ tr!\\!/!;

 unless($path eq "/")
 {
  $path = substr($path,0,-1) if($path =~ m!/$!);
  $path = substr($path,0,rindex($path,"/"));
  $path = $path."/";
 }

 return $path;
}

# it's true, baby ;-)

1;

#
### End ###