package Command;

#
# Dev-Editor - Module Command
#
# Execute Dev-Editor's commands
#
# Author:        Patrick Canterino <patshaping@gmx.net>
# Last modified: 2004-04-25
#

use strict;

use vars qw(@EXPORT);

use File::Access;
use File::Copy;
use File::Path;

use POSIX qw(strftime);
use Tool;

use CGI qw(header);
use HTML::Entities;
use Output;
use Template;

my $script = $ENV{'SCRIPT_NAME'};

my %dispatch = ('show'       => \&exec_show,
                'beginedit'  => \&exec_beginedit,
                'canceledit' => \&exec_canceledit,
                'endedit'    => \&exec_endedit,
                'mkdir'      => \&exec_mkdir,
                'mkfile'     => \&exec_mkfile,
                'upload'     => \&exec_upload,
                'copy'       => \&exec_copy,
                'rename'     => \&exec_rename,
                'remove'     => \&exec_remove,
                'unlock'     => \&exec_unlock,
                'about'      => \&exec_about
               );

### Export ###

use base qw(Exporter);

@EXPORT = qw(exec_command);

# exec_command()
#
# Execute the specified command
#
# Params: 1. Command to execute
#         2. Reference to user input hash
#         3. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_command($$$)
{
 my ($command,$data,$config) = @_;

 return error($config->{'errors'}->{'cmd_unknown'},'/',{COMMAND => $command}) unless($dispatch{$command});

 my $output = &{$dispatch{$command}}($data,$config);
 return $output;
}

# exec_show()
#
# View a directory or a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_show($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};

 my $tpl = new Template;

 if(-d $physical)
 {
  # Create directory listing

  my $direntries = dir_read($physical);
  return error($config->{'dir_read_failed'},upper_path($virtual),{DIR => '$virtual'}) unless($direntries);

  my $files = $direntries->{'files'};
  my $dirs  = $direntries->{'dirs'};

  my $dirlist = "";

  # Create the link to the upper directory
  # (only if we are not in the root directory)

  unless($virtual eq "/")
  {
   my @stat  = stat($physical."/..");

   my $udtpl = new Template;
   $udtpl->read_file($config->{'templates'}->{'dirlist_up'});

   $udtpl->fillin("UPPER_DIR",encode_entities(upper_path($virtual)));
   $udtpl->fillin("DATE",strftime($config->{'timeformat'},localtime($stat[9])));

   $dirlist .= $udtpl->get_template;
  }

  # Directories

  foreach my $dir(@$dirs)
  {
   my @stat      = stat($physical."/".$dir);
   my $virt_path = encode_entities($virtual.$dir."/");

   my $dtpl = new Template;
   $dtpl->read_file($config->{'templates'}->{'dirlist_dir'});

   $dtpl->fillin("DIR",$virt_path);
   $dtpl->fillin("DIR_NAME",$dir);
   $dtpl->fillin("DATE",strftime($config->{'timeformat'},localtime($stat[9])));
   $dtpl->fillin("URL",equal_url($config->{'httproot'},$virt_path));

   $dirlist .= $dtpl->get_template;
  }

  # Files

  foreach my $file(@$files)
  {
   my $phys_path = $physical."/".$file;
   my $virt_path = encode_entities($virtual.$file);

   my @stat      = stat($phys_path);
   my $in_use    = $data->{'uselist'}->in_use($virtual.$file);

   my $ftpl = new Template;
   $ftpl->read_file($config->{'templates'}->{'dirlist_file'});

   $ftpl->fillin("FILE",$virt_path);
   $ftpl->fillin("FILE_NAME",$file);
   $ftpl->fillin("SIZE",$stat[7]);
   $ftpl->fillin("DATE",strftime($config->{'timeformat'},localtime($stat[9])));
   $ftpl->fillin("URL",equal_url($config->{'httproot'},$virt_path));

   $ftpl->parse_if_block("not_readable",not -r $phys_path);
   $ftpl->parse_if_block("binary",-B $phys_path);
   $ftpl->parse_if_block("readonly",not -w $phys_path);

   $ftpl->parse_if_block("viewable",-r $phys_path && -T $phys_path);
   $ftpl->parse_if_block("editable",-w $phys_path && -r $phys_path && -T $phys_path && not $in_use);

   $ftpl->parse_if_block("in_use",$in_use);
   $ftpl->parse_if_block("unused",not $in_use);

   $dirlist .= $ftpl->get_template;
  }

  $tpl->read_file($config->{'templates'}->{'dirlist'});

  $tpl->fillin("DIRLIST",$dirlist);
  $tpl->fillin("DIR",$virtual);
  $tpl->fillin("SCRIPT",$script);
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
 }
 else
 {
  # View a file

  return error($config->{'errors'}->{'noview'},upper_path($virtual)) unless(-r $physical);

  # Check on binary files
  # We have to do it in this way, or empty files
  # will be recognized as binary files

  unless(-T $physical)
  {
   # Binary file

   return error($config->{'errors'}->{'binary'},upper_path($virtual));
  }
  else
  {
   # Text file

   my $content =  file_read($physical);
   $$content   =~ s/\015\012|\012|\015/\n/g;

   $tpl->read_file($config->{'templates'}->{'viewfile'});

   $tpl->fillin("FILE",$virtual);
   $tpl->fillin("DIR",upper_path($virtual));
   $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
   $tpl->fillin("SCRIPT",$script);
   $tpl->fillin("CONTENT",encode_entities($$content));
  }
 }

 my $output  = header(-type => "text/html");
 $output    .= $tpl->get_template;

 return \$output;
}

# exec_beginedit
#
# Lock a file and display a form to edit it
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_beginedit($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $uselist        = $data->{'uselist'};

 return error($config->{'errors'}->{'editdir'},upper_path($virtual))                   if(-d $physical);
 return error($config->{'errors'}->{'in_use'},upper_path($virtual),{FILE => $virtual}) if($uselist->in_use($virtual));
 return error($config->{'errors'}->{'noedit'},upper_path($virtual))                    unless(-r $physical && -w $physical);

 # Check on binary files

 unless(-T $physical)
 {
  # Binary file

  return error($config->{'errors'}->{'binary'},upper_path($virtual));
 }
 else
 {
  # Text file

  $uselist->add_file($virtual);
  $uselist->save;

  my $content =  file_read($physical);
  $$content   =~ s/\015\012|\012|\015/\n/g;

  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'editfile'});

  $tpl->fillin("FILE",$virtual);
  $tpl->fillin("DIR",upper_path($virtual));
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
  $tpl->fillin("SCRIPT",$script);
  $tpl->fillin("CONTENT",encode_entities($$content));

  my $output = header(-type => "text/html");
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_canceledit()
#
# Abort file editing
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_canceledit($$)
{
 my ($data,$config) = @_;
 my $virtual        = $data->{'virtual'};

 file_unlock($data->{'uselist'},$virtual);
 return devedit_reload({command => 'show', file => upper_path($virtual)});
}

# exec_endedit()
#
# Save a file, unlock it and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_endedit($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $content        = $data->{'cgi'}->param('filecontent');
 my $uselist        = $data->{'uselist'};

 # Normalize newlines

 $content =~ s/\015\012|\012|\015/\n/g;

 if($data->{'cgi'}->param('encode_iso'))
 {
  # Encode all ISO-8859-1 special chars

  $content = encode_entities($content,"\200-\377");
 }

 if($data->{'cgi'}->param('saveas'))
 {
  # Create the new filename

  $physical = $data->{'new_physical'};
  $virtual  = $data->{'new_virtual'};

  # Check if someone else is editing the new file

  return error($config->{'errors'}->{'in_use'},upper_path($virtual),{FILE => $virtual}) if($uselist->in_use($virtual));
 }

 return error($config->{'errors'}->{'editdir'},upper_path($virtual)) if(-d $physical);
 return error($config->{'errors'}->{'noedit'}, upper_path($virtual)) unless(-r $physical && -w $physical);

 if(file_save($physical,\$content))
 {
  # Saving of the file was successful - so unlock it!

  file_unlock($uselist,$data->{'virtual'});
  #                    ^^^^^^^^^^^^^^^^^^
  # Maybe the user saved the file using another filename...
  # But we have to unlock the original file!

  return devedit_reload({command => 'show', file => upper_path($virtual)});
 }
 else
 {
  return error($config->{'errors'}->{'edit_failed'},upper_path($virtual),{FILE => $virtual});
 }
}

# exec_mkfile()
#
# Create a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_mkfile($$)
{
 my ($data,$config) = @_;
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

 file_create($new_physical) or return error($config->{'errors'}->{'mkfile_failed'},$dir,{FILE => $new_virtual});
 return devedit_reload({command => 'show', file => $dir});
}

# exec_mkdir()
#
# Create a directory and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_mkdir($$)
{
 my ($data,$config) = @_;
 my $new_physical   = $data->{'new_physical'};
 my $new_virtual    = $data->{'new_virtual'};
 my $dir            = upper_path($new_virtual);
 $new_virtual       = encode_entities($new_virtual);

 return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

 mkdir($new_physical,0777) or return error($config->{'errors'}->{'mkdir_failed'},$dir,{DIR => $new_virtual});
 return devedit_reload({command => 'show', file => $dir});
}

# exec_upload()
#
# Upload a file
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_upload($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $cgi            = $data->{'cgi'};

 if(my $uploaded_file = $cgi->param('uploaded_file'))
 {
  # Process file upload

  my $filename  = file_name($uploaded_file);
  my $file_phys = $physical."/".$filename;
  my $file_virt = $virtual."".$filename;

  return error($config->{'errors'}->{'file_exists'},$virtual,{FILE => $file_virt}) if(-e $file_phys);

  my $ascii     = $cgi->param('ascii');
  my $handle    = $cgi->upload('uploaded_file');

  local *FILE;

  open(FILE,">$file_phys") or return error($config->{'errors'}->{'mkfile_failed'},$virtual,{FILE => $file_virt});
  binmode(FILE) unless($ascii);

  my $data;

  while(read($handle,$data,1024))
  {
   $data =~ s/\015\012|\012|\015/\n/g if($ascii);
   print FILE $data;
  }

  close(FILE);

  return devedit_reload({command => "show", file => $virtual});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'upload'});

  $tpl->fillin("DIR",$virtual);
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
  $tpl->fillin("SCRIPT",$script);

  my $output = header(-type => "text/html");
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_copy()
#
# Copy a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_copy($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = encode_entities($data->{'virtual'});
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'nocopy'}) unless(-r $physical);

 if($new_physical)
 {
  my $new_virtual = $data->{'new_virtual'};
  my $dir         = upper_path($new_virtual);
  $new_virtual    = encode_entities($new_virtual);

  if(-e $new_physical)
  {
   return error($config->{'errors'}->{'exist_edited'},$dir,{FILE => $new_virtual}) if($data->{'uselist'}->in_use($data->{'new_virtual'}));

   if(-d $new_physical)
   {
    return error($config->{'errors'}->{'dircopy'});
   }
   elsif(not $data->{'cgi'}->param('confirmed'))
   {
    my $tpl = new Template;
    $tpl->read_file($config->{'templates'}->{'confirm_replace'});

    $tpl->fillin("FILE",$virtual);
    $tpl->fillin("NEW_FILE",$new_virtual);
    $tpl->fillin("NEW_FILENAME",file_name($new_virtual));
    $tpl->fillin("NEW_DIR",$dir);
    $tpl->fillin("DIR",upper_path($virtual));

    $tpl->fillin("COMMAND","copy");
    $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
    $tpl->fillin("SCRIPT",$script);

    my $output = header(-type => "text/html");
    $output   .= $tpl->get_template;

    return \$output;
   }
  }

  copy($physical,$new_physical) or return error($config->{'errors'}->{'copy_failed'},upper_path($virtual),{FILE => $virtual, NEW_FILE => $new_virtual});
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'copyfile'});

  $tpl->fillin("FILE",$virtual);
  $tpl->fillin("DIR",upper_path($virtual));
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
  $tpl->fillin("SCRIPT",$script);

  my $output = header(-type => "text/html");
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_rename()
#
# Rename/move a file and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_rename($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'in_use'},upper_path($virtual),{FILE => $virtual}) if($data->{'uselist'}->in_use($virtual));

 if($new_physical)
 {
  my $new_virtual = $data->{'new_virtual'};
  my $dir         = upper_path($new_virtual);
  $new_virtual    = encode_entities($new_virtual);

  if(-e $new_physical)
  {
   return error($config->{'errors'}->{'exist_edited'},$dir,{FILE => $new_virtual}) if($data->{'uselist'}->in_use($data->{'new_virtual'}));

   if(-d $new_physical)
   {
    return error($config->{'errors'}->{'dircopy'});
   }
   elsif(not $data->{'cgi'}->param('confirmed'))
   {
    my $tpl = new Template;
    $tpl->read_file($config->{'templates'}->{'confirm_replace'});

    $tpl->fillin("FILE",$virtual);
    $tpl->fillin("NEW_FILE",$new_virtual);
    $tpl->fillin("NEW_FILENAME",file_name($new_virtual));
    $tpl->fillin("NEW_DIR",$dir);
    $tpl->fillin("DIR",upper_path($virtual));

    $tpl->fillin("COMMAND","rename");
    $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
    $tpl->fillin("SCRIPT",$script);

    my $output = header(-type => "text/html");
    $output   .= $tpl->get_template;

    return \$output;
   }
  }

  rename($physical,$new_physical) or return error($config->{'errors'}->{'rename_failed'},upper_path($virtual),{FILE => $virtual, NEW_FILE => $new_virtual});
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'renamefile'});

  $tpl->fillin("FILE",$virtual);
  $tpl->fillin("DIR",upper_path($virtual));
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
  $tpl->fillin("SCRIPT",$script);

  my $output = header(-type => "text/html");
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_remove()
#
# Remove a file or a directory and return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_remove($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};

 if(-d $physical)
 {
  # Remove a directory

  if($data->{'cgi'}->param('confirmed'))
  {
   rmtree($physical);
   return devedit_reload({command => 'show', file => upper_path($virtual)});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmdir'});

   $tpl->fillin("DIR",$virtual);
   $tpl->fillin("UPPER_DIR",upper_path($virtual));
   $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
   $tpl->fillin("SCRIPT",$script);

   my $output = header(-type => "text/html");
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
 else
 {
  # Remove a file

  return error($config->{'errors'}->{'in_use'},upper_path($virtual),{FILE => $virtual}) if($data->{'uselist'}->in_use($virtual));

  if($data->{'cgi'}->param('confirmed'))
  {
   unlink($physical) or return error($config->{'errors'}->{'delete_failed'},upper_path($virtual),{FILE => $virtual});
   return devedit_reload({command => 'show', file => upper_path($virtual)});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmfile'});

   $tpl->fillin("FILE",$virtual);
   $tpl->fillin("DIR",upper_path($virtual));
   $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
   $tpl->fillin("SCRIPT",$script);

   my $output = header(-type => "text/html");
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
}

# exec_unlock()
#
# Remove a file from the list of used files and
# return to directory view
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_unlock($$)
{
 my ($data,$config) = @_;
 my $virtual        = $data->{'virtual'};

 if($data->{'cgi'}->param('confirmed'))
 {
  file_unlock($data->{'uselist'},$virtual);
  return devedit_reload({command => 'show', file => upper_path($virtual)});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'confirm_unlock'});

  $tpl->fillin("FILE",$virtual);
  $tpl->fillin("DIR",upper_path($virtual));
  $tpl->fillin("URL",equal_url($config->{'httproot'},$virtual));
  $tpl->fillin("SCRIPT",$script);

  my $output = header(-type => "text/html");
  $output   .= $tpl->get_template;

  return \$output;
 }
}

# exec_about()
#
# Display some information about Dev-Editor
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_about($$)
{
 my ($data,$config) = @_;

 my $tpl = new Template;
 $tpl->read_file($config->{'templates'}->{'about'});

 $tpl->fillin("SCRIPT",$script);

 # Dev-Editor's version number

 $tpl->fillin("VERSION",$data->{'version'});

 # Some path information

 $tpl->fillin("SCRIPT_PHYS",$ENV{'SCRIPT_FILENAME'});
 $tpl->fillin("CONFIG_PATH",$data->{'configfile'});
 $tpl->fillin("FILE_ROOT",$config->{'fileroot'});
 $tpl->fillin("HTTP_ROOT",$config->{'httproot'});

 # Perl

 $tpl->fillin("PERL_PROG",$^X);
 $tpl->fillin("PERL_VER",sprintf("%vd",$^V));

 # Information about the server

 $tpl->fillin("HTTPD",$ENV{'SERVER_SOFTWARE'});
 $tpl->fillin("OS",$^O);
 $tpl->fillin("TIME",strftime($config->{'timeformat'},localtime));

 # Process information

 $tpl->fillin("PID",$$);

 # Check if the functions getpwuid() and getgrgid() are available

 if(eval("getpwuid(0)") && eval("getgrgid(0)"))
 {
  # Dev-Editor is running on a system which allows users and groups
  # So we display the user and the group of our process

  $tpl->parse_if_block("users",1);

  # ID's of user and group

  $tpl->fillin("UID",$<);
  $tpl->fillin("GID",$();

  # Names of user and group

  $tpl->fillin("USER",getpwuid($<));
  $tpl->fillin("GROUP",getgrgid($());
 }
 else
 {
  $tpl->parse_if_block("users",0);
 }

 my $output = header(-type => "text/html");
 $output   .= $tpl->get_template;

 return \$output;
}

# it's true, baby ;-)

1;

#
### End ###