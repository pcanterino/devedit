package Output;

#
# Dev-Editor - Module Output
#
# HTML generating routines
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-05-09
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

use CGI qw(header
           escape);

use Template;
use Tool;

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
#            Please use the unencoded form of the string!
#         3. Hash reference: Template variables (optional)
#
# Return: Formatted message (Scalar Reference)

sub error($;$$)
{
 my ($message,$path,$vars) = @_;

 my $tpl = new Template;
 $tpl->read_file($tpl_error);

 $tpl->set_var('ERROR',$message);
 $tpl->set_var('BACK',encode_html($path));
 $tpl->set_var('BACK_URL',escape($path));
 $tpl->set_var('SCRIPT',encode_html($ENV{'SCRIPT_NAME'}));

 $tpl->parse_if_block('dir',defined $path);

 if(ref($vars) eq 'HASH')
 {
  while(my ($key,$value) = each(%$vars))
  {
   $tpl->set_var($key,$value);
  }
 }

 $tpl->parse();

 my $output = header(-type => 'text/html');
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