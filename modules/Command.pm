package Command;

#
# Dev-Editor - Module Command
#
# Execute Dev-Editor's commands
#
# Author:        Patrick Canterino <patrick@patshaping.de>
# Last modified: 2005-01-06
#

use strict;

use vars qw(@EXPORT);

use File::Access;
use File::Copy;
use File::Path;

use POSIX qw(strftime);
use Tool;

use CGI qw(header
           escape);

use HTML::Entities;
use Output;
use Template;

my $script = encode_entities($ENV{'SCRIPT_NAME'});
my $users  = eval('getpwuid(0)') && eval('getgrgid(0)');

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
                'chprop'     => \&exec_chprop,
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

 foreach(keys(%dispatch))
 {
  if(lc($_) eq lc($command))
  {
   my $output = &{$dispatch{$_}}($data,$config);
   return $output;
  }
 }

 return error($config->{'errors'}->{'cmd_unknown'},'/',{COMMAND => encode_entities($command)});
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
 my $upper_path     = encode_entities(upper_path($virtual));
 my $uselist        = $data->{'uselist'};

 my $tpl = new Template;

 if(-d $physical)
 {
  # Create directory listing

  return error($config->{'errors'}->{'no_dir_access'},$upper_path) unless(-r $physical && -x $physical);

  my $direntries = dir_read($physical);
  return error($config->{'dir_read_fail'},$upper_path,{DIR => encode_entities($virtual)}) unless($direntries);

  my $files = $direntries->{'files'};
  my $dirs  = $direntries->{'dirs'};

  my $dir_writeable = -w $physical;

  my $dirlist = '';

  my $filter1 = $data->{'cgi'}->param('filter') || '*';        # The real wildcard
  my $filter2 = ($filter1 && $filter1 ne '*') ? $filter1 : ''; # Wildcard for output

  # Create the link to the upper directory
  # (only if we are not in the root directory)

  unless($virtual eq '/')
  {
   my @stat  = stat($physical.'/..');

   my $udtpl = new Template;
   $udtpl->read_file($config->{'templates'}->{'dirlist_up'});

   $udtpl->fillin('UPPER_DIR',$upper_path);
   $udtpl->fillin('DATE',encode_entities(strftime($config->{'timeformat'},localtime($stat[9]))));

   $dirlist .= $udtpl->get_template;
  }

  # Directories

  foreach my $dir(@$dirs)
  {
   next unless(dos_wildcard_match($filter1,$dir));

   my $phys_path = $physical.'/'.$dir;
   my $virt_path = encode_entities($virtual.$dir.'/');

   my @stat      = stat($phys_path);

   my $dtpl = new Template;
   $dtpl->read_file($config->{'templates'}->{'dirlist_dir'});

   $dtpl->fillin('DIR',$virt_path);
   $dtpl->fillin('DIR_NAME',encode_entities($dir));
   $dtpl->fillin('DATE',encode_entities(strftime($config->{'timeformat'},localtime($stat[9]))));
   $dtpl->fillin('URL',equal_url(encode_entities($config->{'httproot'}),$virt_path));

   $dtpl->parse_if_block('readable',-r $phys_path && -x $phys_path);
   $dtpl->parse_if_block('users',$users && -o $phys_path);

   $dirlist .= $dtpl->get_template;
  }

  # Files

  foreach my $file(@$files)
  {
   next unless(dos_wildcard_match($filter1,$file));

   my $phys_path = $physical.'/'.$file;
   my $virt_path = encode_entities($virtual.$file);

   my @stat      = stat($phys_path);
   my $in_use    = $uselist->in_use($virtual.$file);
   my $too_large = $config->{'max_file_size'} && $stat[7] > $config->{'max_file_size'};

   my $ftpl = new Template;
   $ftpl->read_file($config->{'templates'}->{'dirlist_file'});

   $ftpl->fillin('FILE',$virt_path);
   $ftpl->fillin('FILE_NAME',encode_entities($file));
   $ftpl->fillin('SIZE',$stat[7]);
   $ftpl->fillin('DATE',encode_entities(strftime($config->{'timeformat'},localtime($stat[9]))));
   $ftpl->fillin('URL',equal_url(encode_entities($config->{'httproot'}),$virt_path));

   $ftpl->parse_if_block('not_readable',not -r $phys_path);
   $ftpl->parse_if_block('binary',-B $phys_path);
   $ftpl->parse_if_block('readonly',not -w $phys_path);

   $ftpl->parse_if_block('viewable',-r $phys_path && -T $phys_path && not $too_large);
   $ftpl->parse_if_block('editable',(-r $phys_path && -w $phys_path && -T $phys_path && not $too_large) && not $in_use);

   $ftpl->parse_if_block('in_use',$in_use);
   $ftpl->parse_if_block('unused',not $in_use);

   $ftpl->parse_if_block('too_large',$config->{'max_file_size'} && $stat[7] > $config->{'max_file_size'});

   $ftpl->parse_if_block('users',$users && -o $phys_path);

   $dirlist .= $ftpl->get_template;
  }

  $tpl->read_file($config->{'templates'}->{'dirlist'});

  $tpl->fillin('DIRLIST',$dirlist);
  $tpl->fillin('DIR',encode_entities($virtual));
  $tpl->fillin('SCRIPT',$script);
  $tpl->fillin('URL',encode_entities(equal_url($config->{'httproot'},$virtual)));

  $tpl->fillin('FILTER',encode_entities($filter2));
  $tpl->fillin('FILTER_URL',escape($filter2));

  $tpl->parse_if_block('dir_writeable',$dir_writeable);
  $tpl->parse_if_block('filter',$filter2);
 }
 else
 {
  # View a file

  return error($config->{'errors'}->{'no_view'},$upper_path) unless(-r $physical);

  # Check on binary files
  # We have to do it in this way or empty files will be recognized
  # as binary files

  return error($config->{'errors'}->{'binary'},$upper_path) unless(-T $physical);

  # Is the file too large?

  return error($config->{'errors'}->{'file_too_large'},$upper_path,{SIZE => $config->{'max_file_size'}}) if($config->{'max_file_size'} && -s $physical > $config->{'max_file_size'});

  # View the file

  my $content =  file_read($physical);
  $$content   =~ s/\015\012|\012|\015/\n/g;

  $tpl->read_file($config->{'templates'}->{'viewfile'});

  $tpl->fillin('FILE',encode_entities($virtual));
  $tpl->fillin('DIR',$upper_path);
  $tpl->fillin('URL',encode_entities(equal_url($config->{'httproot'},$virtual)));
  $tpl->fillin('SCRIPT',$script);

  $tpl->parse_if_block('editable',-w $physical && $uselist->unused($virtual));

  $tpl->fillin('CONTENT',encode_entities($$content));
 }

 my $output  = header(-type => 'text/html');
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
 my $dir            = upper_path($virtual);
 my $uselist        = $data->{'uselist'};

 return error($config->{'errors'}->{'editdir'},$dir)                    if(-d $physical);
 return error($config->{'errors'}->{'in_use'}, $dir,{FILE => $virtual}) if($uselist->in_use($virtual));
 return error($config->{'errors'}->{'no_edit'},$dir)                    unless(-r $physical && -w $physical);

 # Check on binary files

 return error($config->{'errors'}->{'binary'},$dir) unless(-T $physical);

 # Is the file too large?

 return error($config->{'errors'}->{'file_too_large'},$dir,{SIZE => $config->{'max_file_size'}}) if($config->{'max_file_size'} && -s $physical > $config->{'max_file_size'});

 # Lock the file...

 $uselist->add_file($virtual);
 $uselist->save;

 # ... and show the editing form

 my $content =  file_read($physical);
 $$content   =~ s/\015\012|\012|\015/\n/g;

 my $tpl = new Template;
 $tpl->read_file($config->{'templates'}->{'editfile'});

 $tpl->fillin('FILE',$virtual);
 $tpl->fillin('DIR',$dir);
 $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
 $tpl->fillin('SCRIPT',$script);
 $tpl->fillin('CONTENT',encode_entities($$content));

 my $output = header(-type => 'text/html');
 $output   .= $tpl->get_template;

 return \$output;
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
 my $dir            = upper_path($virtual);
 my $content        = $data->{'cgi'}->param('filecontent');
 my $uselist        = $data->{'uselist'};

 # We already unlock the file at the beginning of the subroutine,
 # because if we have to abort this routine, the file keeps locked.
 # No other user of Dev-Editor will access the file during this
 # routine because of the concept of File::UseList.

 file_unlock($uselist,$virtual);

 # Normalize newlines

 $content =~ s/\015\012|\012|\015/\n/g;

 if($data->{'cgi'}->param('encode_iso'))
 {
  # Encode all ISO-8859-1 special chars

  $content = encode_entities($content,"\200-\377");
 }

 if($data->{'cgi'}->param('saveas') && $data->{'new_physical'} ne '' && $data->{'new_virtual'} ne '')
 {
  # Create the new filename

  $physical = $data->{'new_physical'};
  $virtual  = $data->{'new_virtual'};

  # Check if someone else is editing the new file

  return error($config->{'errors'}->{'in_use'},$dir,{FILE => $virtual}) if($uselist->in_use($virtual));
 }

 return error($config->{'errors'}->{'editdir'},$dir)        if(-d $physical);
 return error($config->{'errors'}->{'no_edit'},$dir)        if(-e $physical && !(-r $physical && -w $physical));
 return error($config->{'errors'}->{'text_to_binary'},$dir) unless(-T $physical);

 if(file_save($physical,\$content))
 {
  # Saving of the file was successful!

  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  return error($config->{'errors'}->{'edit_failed'},$dir,{FILE => $virtual});
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

 if($new_physical)
 {
  return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

  file_create($new_physical) or return error($config->{'errors'}->{'mkfile_failed'},$dir,{FILE => $new_virtual});
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'mkfile'});

  $tpl->fillin('DIR','/');
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
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

 if($new_physical)
 {
  return error($config->{'errors'}->{'file_exists'},$dir,{FILE => $new_virtual}) if(-e $new_physical);

  mkdir($new_physical,0777) or return error($config->{'errors'}->{'mkdir_failed'},$dir,{DIR => $new_virtual});
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'mkdir'});

  $tpl->fillin('DIR','/');
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
 }
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

 return error($config->{'errors'}->{'no_directory'},upper_path($virtual),{FILE => $virtual}) unless(-d $physical);
 return error($config->{'errors'}->{'dir_no_create'},$virtual,{DIR => $virtual})             unless(-w $physical);

 if(my $uploaded_file = $cgi->param('uploaded_file'))
 {
  # Process file upload

  my $filename  = file_name($uploaded_file);
  my $file_phys = $physical.'/'.$filename;
  my $file_virt = $virtual.$filename;

  return error($config->{'errors'}->{'in_use'},$virtual,{FILE => $file_virt}) if($data->{'uselist'}->in_use($file_virt));

  if(-e $file_phys)
  {
   return error($config->{'errors'}->{'dir_replace'},$virtual)                         if(-d $file_phys);
   return error($config->{'errors'}->{'exist_no_write'},$virtual,{FILE => $file_virt}) unless(-w $file_phys);
   return error($config->{'errors'}->{'file_exists'},$virtual,{FILE => $file_virt})    unless($cgi->param('overwrite'));
  }

  my $ascii     = $cgi->param('ascii');
  my $handle    = $cgi->upload('uploaded_file');

  return error($config->{'errors'}->{'invalid_upload'},$virtual) unless($handle);

  # Read transferred file and write it to disk

  read($handle, my $data, -s $handle);
  $data =~ s/\015\012|\012|\015/\n/g if($ascii); # Replace line separators if transferring in ASCII mode
  file_save($file_phys,\$data,not $ascii) or return error($config->{'errors'}->{'mkfile_failed'},$virtual,{FILE => $file_virt});

  return devedit_reload({command => 'show', file => $virtual});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'upload'});

  $tpl->fillin('DIR',$virtual);
  $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
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
 my $dir            = upper_path($virtual);
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'dircopy'},$dir) if(-d $physical);
 return error($config->{'errors'}->{'no_copy'},$dir) unless(-r $physical);

 if($new_physical)
 {
  my $new_virtual = $data->{'new_virtual'};
  my $new_dir     = upper_path($new_virtual);
  $new_virtual    = encode_entities($new_virtual);

  if(-e $new_physical)
  {
   return error($config->{'errors'}->{'exist_edited'},$new_dir,{FILE => $new_virtual})   if($data->{'uselist'}->in_use($data->{'new_virtual'}));
   return error($config->{'errors'}->{'dir_replace'},$new_dir)                           if(-d $new_physical);
   return error($config->{'errors'}->{'exist_no_write'},$new_dir,{FILE => $new_virtual}) unless(-w $new_physical);

   if(not $data->{'cgi'}->param('confirmed'))
   {
    my $tpl = new Template;
    $tpl->read_file($config->{'templates'}->{'confirm_replace'});

    $tpl->fillin('FILE',$virtual);
    $tpl->fillin('NEW_FILE',$new_virtual);
    $tpl->fillin('NEW_FILENAME',file_name($new_virtual));
    $tpl->fillin('NEW_DIR',$new_dir);
    $tpl->fillin('DIR',$dir);

    $tpl->fillin('COMMAND','copy');
    $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
    $tpl->fillin('SCRIPT',$script);

    my $output = header(-type => 'text/html');
    $output   .= $tpl->get_template;

    return \$output;
   }
  }

  copy($physical,$new_physical) or return error($config->{'errors'}->{'copy_failed'},$dir,{FILE => $virtual, NEW_FILE => $new_virtual});
  return devedit_reload({command => 'show', file => $new_dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'copyfile'});

  $tpl->fillin('FILE',$virtual);
  $tpl->fillin('DIR',$dir);
  $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
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
 my $dir            = upper_path($virtual);
 my $new_physical   = $data->{'new_physical'};

 return error($config->{'errors'}->{'rename_root'},'/')                if($virtual eq '/');
 return error($config->{'errors'}->{'no_rename'},$dir)                 unless(-w upper_path($physical));
 return error($config->{'errors'}->{'in_use'},$dir,{FILE => $virtual}) if($data->{'uselist'}->in_use($virtual));

 if($new_physical)
 {
  my $new_virtual = $data->{'new_virtual'};
  my $new_dir     = upper_path($new_virtual);
  $new_virtual    = encode_entities($new_virtual);

  if(-e $new_physical)
  {
   return error($config->{'errors'}->{'exist_edited'},$new_dir,{FILE => $new_virtual})   if($data->{'uselist'}->in_use($data->{'new_virtual'}));
   return error($config->{'errors'}->{'dir_replace'},$new_dir)                           if(-d $new_physical);
   return error($config->{'errors'}->{'exist_no_write'},$new_dir,{FILE => $new_virtual}) unless(-w $new_physical);

   if(not $data->{'cgi'}->param('confirmed'))
   {
    my $tpl = new Template;
    $tpl->read_file($config->{'templates'}->{'confirm_replace'});

    $tpl->fillin('FILE',$virtual);
    $tpl->fillin('NEW_FILE',$new_virtual);
    $tpl->fillin('NEW_FILENAME',file_name($new_virtual));
    $tpl->fillin('NEW_DIR',$new_dir);
    $tpl->fillin('DIR',$dir);

    $tpl->fillin('COMMAND','rename');
    $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
    $tpl->fillin('SCRIPT',$script);

    my $output = header(-type => 'text/html');
    $output   .= $tpl->get_template;

    return \$output;
   }
  }

  rename($physical,$new_physical) or return error($config->{'errors'}->{'rename_failed'},$dir,{FILE => $virtual, NEW_FILE => $new_virtual});
  return devedit_reload({command => 'show', file => $new_dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'renamefile'});

  $tpl->fillin('FILE',$virtual);
  $tpl->fillin('DIR',$dir);
  $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
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
 my $dir            = upper_path($virtual);

 return error($config->{'errors'}->{'remove_root'},'/') if($virtual eq '/');
 return error($config->{'errors'}->{'no_delete'},$dir)  unless(-w upper_path($physical));

 if(-d $physical)
 {
  # Remove a directory

  if($data->{'cgi'}->param('confirmed'))
  {
   rmtree($physical);
   return devedit_reload({command => 'show', file => $dir});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmdir'});

   $tpl->fillin('DIR',$virtual);
   $tpl->fillin('UPPER_DIR',$dir);
   $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
 else
 {
  # Remove a file

  return error($config->{'errors'}->{'in_use'},$dir,{FILE => $virtual}) if($data->{'uselist'}->in_use($virtual));

  if($data->{'cgi'}->param('confirmed'))
  {
   unlink($physical) or return error($config->{'errors'}->{'delete_failed'},$dir,{FILE => $virtual});
   return devedit_reload({command => 'show', file => $dir});
  }
  else
  {
   my $tpl = new Template;
   $tpl->read_file($config->{'templates'}->{'confirm_rmfile'});

   $tpl->fillin('FILE',$virtual);
   $tpl->fillin('DIR',$dir);
   $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
   $tpl->fillin('SCRIPT',$script);

   my $output = header(-type => 'text/html');
   $output   .= $tpl->get_template;

   return \$output;
  }
 }
}

# exec_chprop()
#
# Change the mode and the group of a file or a directory
#
# Params: 1. Reference to user input hash
#         2. Reference to config hash
#
# Return: Output of the command (Scalar Reference)

sub exec_chprop($$)
{
 my ($data,$config) = @_;
 my $physical       = $data->{'physical'};
 my $virtual        = $data->{'virtual'};
 my $dir            = upper_path($virtual);

 return error($config->{'errors'}->{'no_users'},$dir,{FILE => $virtual})  unless($users);
 return error($config->{'errors'}->{'chprop_root'},'/')                   if($virtual eq '/');
 return error($config->{'errors'}->{'not_owner'},$dir,{FILE => $virtual}) unless(-o $physical);
 return error($config->{'errors'}->{'in_use'},$dir,{FILE => $virtual})    if($data->{'uselist'}->in_use($virtual));

 my $cgi   = $data->{'cgi'};
 my $mode  = $cgi->param('mode');
 my $group = $cgi->param('group');

 if($mode || $group)
 {
  if($mode)
  {
   # Change the mode

   chmod(oct($mode),$physical);
  }

  if($group)
  {
   # Change the group using the `chgrp` system command

   return error($config->{'errors'}->{'invalid_group'},$dir,{GROUP => encode_entities($group)}) unless($group =~ /^[a-z0-9_]+[a-z0-9_-]*$/i);
   system('chgrp',$group,$physical);
  }

  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  # Display the form

  my @stat = stat($physical);
  my $mode = $stat[2];
  my $gid  = $stat[5];

  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'chprop'});

  # Insert file properties into the template

  $tpl->fillin('MODE_OCTAL',substr(sprintf('%04o',$mode),-4));
  $tpl->fillin('MODE_STRING',mode_string($mode));
  $tpl->fillin('GID',$gid);

  if(my $group = getgrgid($gid))
  {
   $tpl->fillin('GROUP',encode_entities($group));
   $tpl->parse_if_block('group_detected',1);
  }
  else
  {
   $tpl->parse_if_block('group_detected',0);
  }

  # Insert other information

  $tpl->fillin('FILE',$virtual);
  $tpl->fillin('DIR',$dir);
  $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
  $output   .= $tpl->get_template;

  return \$output;
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
 my $uselist        = $data->{'uselist'};
 my $dir            = upper_path($virtual);

 return devedit_reload({command => 'show', file => $dir}) if($uselist->unused($virtual));

 if($data->{'cgi'}->param('confirmed'))
 {
  file_unlock($uselist,$virtual);
  return devedit_reload({command => 'show', file => $dir});
 }
 else
 {
  my $tpl = new Template;
  $tpl->read_file($config->{'templates'}->{'confirm_unlock'});

  $tpl->fillin('FILE',$virtual);
  $tpl->fillin('DIR',$dir);
  $tpl->fillin('URL',equal_url($config->{'httproot'},$virtual));
  $tpl->fillin('SCRIPT',$script);

  my $output = header(-type => 'text/html');
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

 $tpl->fillin('SCRIPT',$script);

 # Dev-Editor's version number

 $tpl->fillin('VERSION',$data->{'version'});

 # Some path information

 $tpl->fillin('SCRIPT_PHYS',encode_entities($ENV{'SCRIPT_FILENAME'}));
 $tpl->fillin('CONFIG_PATH',encode_entities($data->{'configfile'}));
 $tpl->fillin('FILE_ROOT',  encode_entities($config->{'fileroot'}));
 $tpl->fillin('HTTP_ROOT',  encode_entities($config->{'httproot'}));

 # Perl

 $tpl->fillin('PERL_PROG',encode_entities($^X));
 $tpl->fillin('PERL_VER', sprintf('%vd',$^V));

 # Information about the server

 $tpl->fillin('HTTPD',encode_entities($ENV{'SERVER_SOFTWARE'}));
 $tpl->fillin('OS',   encode_entities($^O));
 $tpl->fillin('TIME', encode_entities(strftime($config->{'timeformat'},localtime)));

 # Process information

 $tpl->fillin('PID',$$);

 # Check if the functions getpwuid() and getgrgid() are available

 if($users)
 {
  # Dev-Editor is running on a system which allows users and groups
  # So we display the user and the group of our process

  my $uid = POSIX::getuid;
  my $gid = POSIX::getgid;

  $tpl->parse_if_block('users',1);

  # ID's of user and group

  $tpl->fillin('UID',$uid);
  $tpl->fillin('GID',$gid);

  # Names of user and group

  if(my $user = getpwuid($uid))
  {
   $tpl->fillin('USER',encode_entities($user));
   $tpl->parse_if_block('user_detected',1);
  }
  else
  {
   $tpl->parse_if_block('user_detected',0);
  }

  if(my $group = getgrgid($gid))
  {
   $tpl->fillin('GROUP',encode_entities($group));
   $tpl->parse_if_block('group_detected',1);
  }
  else
  {
   $tpl->parse_if_block('group_detected',0);
  }

  # Process umask

  $tpl->fillin('UMASK',sprintf('%04o',umask));
 }
 else
 {
  $tpl->parse_if_block('users',0);
 }

 my $output = header(-type => 'text/html');
 $output   .= $tpl->get_template;

 return \$output;
}

# it's true, baby ;-)

1;

#
### End ###