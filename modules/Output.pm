package Output;

#
# Dev-Editor - Module Output
#
# HTML generating routines
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2004-11-13
#

use strict;

use vars qw(@EXPORT);

use CGI qw(header);
use Tool;

use HTML::Entities;
use Template;

### Export ###

use base qw(Exporter);

@EXPORT = qw(error_template
             error
             abort);

my $tpl_error;

# error_template()
#
# Set the path to the template file used for error messages
# (I'm lazy...)
#
# Params: Template file

sub error_template($)
{
 $tpl_error = shift;
}

# error()
#
# Format an error message
#
# Params: 1. Error message
#         2. Display a link to this path at the bottom of the page (optional)
#         3. Hash reference: Template variables (optional)
#
# Return: Formatted message (Scalar Reference)

sub error($;$$)
{
 my ($message,$path,$vars) = @_;

 my $tpl = new Template;
 $tpl->read_file($tpl_error);

 $tpl->fillin("ERROR",$message);
 $tpl->fillin("DIR",$path);
 $tpl->fillin("SCRIPT",encode_entities($ENV{'SCRIPT_NAME'}));

 $tpl->parse_if_block("dir",defined $path);

 if(ref($vars) eq "HASH")
 {
  while(my ($key,$value) = each(%$vars))
  {
   $tpl->fillin($key,$value);
  }
 }

 my $output = header(-type => "text/html");
 $output   .= $tpl->get_template;

 return \$output;
}

# abort()
#
# Print an error message and exit script
# ^^^^^
#
# Params: 1. Error message
#         2. Display a link to this path at the bottom of the page (optional)
#         3. Hash reference: Template variables (optional)

sub abort($;$$)
{
 my $output = error(shift,shift,shift);
 print $$output;
 exit;
}

# it's true, baby ;-)

1;

#
### End ###