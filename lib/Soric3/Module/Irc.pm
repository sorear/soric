use MooseX::Declare;

# TODO eventually we want to subclass AE:IRC:Client, so that pongs can be
# correctly routed through the queueing system

class Soric3::Module::Irc extends Soric3::Module
    with (Soric3::Role::SendQueueObserver,
          Soric3::Role::SendQueue)
{
    use AnyEvent::IRC::Client;

    has _connects => (
        isa     => 'HashRef[AnyEvent::IRC::Client]',
        is      => 'bare',
        default => sub { {} },
        traits  => ['Hash'],
        handles => { _connection => 'get',
                     _bind_connection => 'set',
                     enum_irc_connections => 'keys' },
    );

    method on_new_sends(Str $conn_name) {
        if ((my $conn = $self->_connection($conn_name))
                && $conn->{heap}->{next_send_time} <= AnyEvent->now) {
            $self->alert;
        }
    }

    method is_ready(Str $conn_name) {
        my $conn = $self->_connection($conn_name)
            || return 0;
        return ($conn->{heap}->{next_send_time} <= AnyEvent->now
             && $conn->registered);
    }

    has _token_watcher => (is => 'rw');

    method react() {
        my $min_timeout = undef;

        for my $conn_name ($self->enum_irc_connections) {
            my $conn = $self->_connection($conn_name);

            while ($conn->{heap}->{next_send_time} <= AnyEvent->now) {

                my ($best_prio, $best_msg, $best_cb) = (0, undef, undef);

                $self->broadcast('SendQueue', 'get_queued_send', $conn_name,
                    sub {
                        my ($prio, $msg, $cb) = @_;

                        if ($prio > $best_prio) {
                            $best_prio = $prio;
                            $best_msg = $msg;
                            $best_cb = $cb;
                        }
                    });

                last if !defined($best_msg);

                $self->log(debug => 'Sending ' . join(",", @$msg) .
                           " to $conn_name");
                $conn->send_srv(@$msg);

                # this could retrigger us, but that's harmless
                $cb->();


                my $time = $conn->{heap}->{next_send_time};
                $time = AnyEvent->now - 10 if $time < AnyEvent->now - 10;

                $time += (2 + length(mkmsg(undef, @$msg)) / 100);

                $conn->{heap}->{next_send_time} = $time;
            }

            if ($conn->{heap}->{next_send_time} > AnyEvent->now) {
                my $delay = $conn->{heap}->{next_send_time} - AnyEvent->now;

                if ($delay < $min_timeout || !defined($min_timeout)) {
                    $min_timeout = $delay;
                }
            }
        }

        if (defined $min_timeout) {
            my $weak_self = $self;
            weaken $weak_self;

            $self->_token_watcher(AnyEvent->timer(after => $min_timeout,
                cb => sub { $weak_self->alert if defined $weak_self }));
        } else {
            $self->_token_watcher(undef);
        }
    }

    method new_connection(Str $tag, Str $host, Num $port, Str $nick,
            Str $password, Str $user, Str $real) {
        my $new_conn = AnyEvent::IRC::Client->new;
        $new_conn->{heap}->{tag} = $tag;
        $self->_bind_connection($tag, $new_conn);
        $new_conn->connect($host, $port,
            { nick => $nick, user => $user, real => $real,
              password => $password });
        $new_conn->{heap}->{backref} = $self;
        Scalar::Util::weaken $new_conn->{heap}->{backref};
        $new_conn->reg_cb(
            registered => sub {
                my $conn = shift;
                $conn->{heap}->{backref}->alert
                    if defined $conn->{heap}->{backref};
            },
            connect => sub {
                my ($conn, $err) = @_;
                return unless defined $err;
                return unless defined $conn->{heap}->{backref};
                $conn->{heap}->{failed} = $err;
                $conn->{heap}->{backref}->broadcast(
                    'ConnectionObserver', 'connection_state_changed',
                    $tag, 'failed');
            },
            # TODO handle connection loss, messages of all kinds
        );

        $self->broadcast('ConnectionObserver', 'connection_created', $tag);
    }

    method delete_connection(Str $tag, Str $reason) {
        my $conn = $self->_connection($tag);

        $conn->send_srv(QUIT => $reason) if $conn->registered;
        $conn->disconnect($reason);

        $self->_unbind_connection($tag);
        $self->broadcast('ConnectionObserver', 'connection_deleted', $tag);
    }
}
