package Tool;

#
# Dev-Editor - Module Tool
#
# Some shared sub routines
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2004-02-03
#

use strict;

use vars qw(@EXPORT);

use CGI qw(redirect);
use Cwd qw(abs_path);
use File::Spec;

### Export ###

use base qw(Exporter);

@EXPORT = qw(check_path
             clean_path
             devedit_reload
             equal_url
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

  my $dir  = upper_path($path);
  my $file = file_name($path);

  $dir  = abs_path($dir);
  $path = $dir."/".$file;
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
 $short_path = "/".$short_path if($short_path !~ m!^/!);
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

# devedit_reload()
#
# Create a HTTP redirection header to load Dev-Editor
# with some other parameters
#
# Params: Hash Reference (will be merged to a query string)
#
# Return: HTTP redirection header (Scalar Reference)

sub devedit_reload($)
{
 my $params = shift;
 my @list;

 while(my ($param,$value) = each(%$params))
 {
  push(@list,$param."=".$value);
 }

 my $query  = join("&",@list);
 my $header = redirect("http://$ENV{'HTTP_HOST'}$ENV{'SCRIPT_NAME'}?$query");

 return \$header;
}

# equal_url()
#
# Create URL equal to a file or directory
#
# Params: 1. HTTP root
#         2. Relative path
#
# Return: Formatted link (String)

sub equal_url($$)
{
 my ($root,$path) = @_;
 my $url;

 $root =~ s!/$!!;
 $path =~ s!^/!!;
 $url  =  $root."/".$path;
 #$url  =  encode_entities($url);

 return $url;
}

# file_name()
#
# Returns the last path of a path
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
# Cut the last part of a path away
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
  $path = substr($path,0,rindex($path,"/")+1);
 }

 return $path;
}

# it's true, baby ;-)

1;

#
### End ###