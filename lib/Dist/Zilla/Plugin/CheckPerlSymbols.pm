package Dist::Zilla::Plugin::CheckPerlSymbols;

use strict; use warnings;

use Moose;
with
  'Dist::Zilla::Role::FileMunger',
  'Dist::Zilla::Role::InstallTool',
  'Dist::Zilla::Role::PrereqSource',
;

use namespace::autoclean;

my @list_opts = qw/
  has_symbol
  lacks_symbol
/;
sub mvp_multivalue_args { @list_opts }

has $_ => (
  isa     => 'ArrayRef[Str]',
  lazy    => 1,
  default => sub { [] },
  traits  => ['Array'],
  handles => { $_ => 'elements' },
) for @list_opts;

around dump_config => sub {
  my ($orig, $self) = @_;
  my $config = $self->$orig;

  $config->{+__PACKAGE__} = +{ map {; $_ => [ $self->$_ ] } @list_opts };

  $config
};

sub register_prereqs {
  my ($self) = @_;
  $self->zilla->register_prereqs( +{
      phase => 'configure',
      type  => 'requires',
    },
    'FFI::Platypus' => '0.32',
  );
}

my %files;
sub munge_files {
  my ($self) = @_;

  my @mfpl = grep 
    {; $_->name eq 'Makefile.PL' or $_->name eq 'Build.PL' } 
      @{ $self->zilla->files };

  for my $mfpl (@mfpl) {
    $self->log_debug('munging ' . $mfpl->name . ' in file gatherer phase');
    $files{ $mfpl->name } = $mfpl;
    $self->_munge_file($mfpl);
  }

  ()
}

sub setup_installer {
  my ($self) = @_;

  my @mfpl = grep 
    {; $_->name eq 'Makefile.PL' or $_->name eq 'Build.PL' } 
      @{ $self->zilla->files };

  unless (@mfpl) {
    $self->log_fatal(
      'No Makefile.PL or Build.PL was found.'
      .' [CheckPerlSymbols] should appear in dist.ini'
      .' after [MakeMaker] or variant!'
    );
  }

  for my $mfpl (@mfpl) {
    next if exists $files{ $mfpl->name };
    $self->log_debug('munging ' . $mfpl->name . ' in setup_installer phase');
    $self->_munge_file($mfpl);
  }

  ()
}

sub _munge_file {
  my ($self, $file) = @_;

  my $orig_content = $file->content;
  $self->log_fatal('could not find position in ' . $file->name . ' to modify!')
    unless $orig_content =~ m/use strict;\nuse warnings;\n\n/g;

  my $pos = pos($orig_content);

  my $insert = "# inserted by " . blessed($self)
    . ' ' . ($self->VERSION || '<self>') . "\n"
    . "use FFI::Platypus;\n"
    . 'my $ffi = FFI::Platypus->new;' ."\n"
    . '$ffi->lib(undef);' ."\n"
  ;

  for my $sym ($self->has_symbol) {
    $insert .= 
        "unless (\$ffi->find_symbol('$sym')) {\n"
      . qq[  warn "Required native symbol '$sym' not found in running perl;]
      . qq[ installation can't continue.\\n"; exit\n]
      . "}\n"
    ; 
  }

  for my $sym ($self->lacks_symbol) {
    $insert .= 
        "if (\$ffi->find_symbol('$sym')) {\n"
      . qq[  warn "Conflicting native symbol '$sym' found in running perl;]
      . qq[ installation can't continue.\\n"; exit\n]
      . "}\n"
    ;
  }
  
  $insert .= "\n";
 
  $file->content( 
    substr($orig_content, 0, $pos) . $insert . substr($orig_content, $pos)
  );
}

__PACKAGE__->meta->make_immutable;

__END__

=pod

=for Pod::Coverage mvp_multivalue_args register_prereqs munge_files setup_installer

=head1 NAME

Dist::Zilla::Plugin::CheckPerlSymbols - Check currently running interpreter for symbols

=head1 SYNOPSIS

In your F<dist.ini>:

    [CheckPerlSymbols]
    has_symbol = pthread_self

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that modifies the F<Makefile.PL> or
F<Build.PL> in your distribution to check for the presence (or lack) of
specified C symbols in the running interpreter via L<FFI::Platypus>.

This is useful for handling certain corner cases related to C-level
interactions.

=head1 CONFIGURATION OPTIONS

=head2 C<has_symbol>

The name of a required symbol.

Can be specified more than once.

=head2 C<lacks_symbol>

The name of a conflicting symbol.

Can be specified more than once.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
