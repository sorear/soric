use MooseX::Declare;

=head1 NAME

Soric3::Role::Send - provide a send queue for the servers

=head1 SYNOPSIS

  with 'Soric3::Role::Send';

  method get_queued_send(Str $tag, CodeRef $cb) {
      if ($self->want_to_moo) {
          $cb->('daemon', [ 'MOO' ], sub { $self->want_to_moo(0) });
      }
  }

=head1 DESCRIPTION

B<Send> allows modules to provide raw sendable lines for the server.  Modules
should be able to produce all immediately sendable lines when requested.  When
the set of available lines changes, implementors should signal all
SendQueueObservers.

=cut

role Soric3::Role::Send {
    requires "get_queued_send";
}
