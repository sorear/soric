use MooseX::Declare;

# TODO we should use unique integer ids here for servers, not reusable tags

role Soric3::Role::SendQueue with Soric3::Role::Send {
    has _send_queues => (
        default  => sub { {} },
        init_arg => undef,
        is       => 'ro',
        isa      => 'HashRef',
    );

    requires "broadcast";

    method queue_message(Str $tag, ArrayRef $msg,
            CodeRef | Str $prio = 'daemon') {
        push @{ $self->_send_queues->{$tag} },
            [ $msg, ref $prio ? $prio : sub { $prio } ];

        $self->broadcast('SendQueueObserver', 'sends_changed', $tag)
            if @{ $self->_send_queues->{$tag} } == 1;
    }

    method get_queued_send(Str $tag, CodeRef $cb) {
        my $head = $self->_send_queues->{$tag}->[0];

        if (defined $head) {
            $cb->($head->[1]->(), $head->[0], sub {
                      shift @{ $self->_send_queues->{$tag} };
                      $self->broadcast('SendQueueObserver',
                              'sends_changed', $tag)
                          if @{ $self->_send_queues->{$tag} } == 0;
                  });
        }
    }
}

1;
