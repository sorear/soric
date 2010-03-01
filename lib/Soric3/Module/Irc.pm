use MooseX::Declare;

# TODO eventually we want to subclass AE:IRC:Client, so that pongs can be
# correctly routed through the queueing system

class Soric3::Module::Irc extends Soric3::Module
    with (Soric3::Role::SendQueueObserver)
{
    use AnyEvent::IRC::Client;

    has _connects => (
        isa     => 'HashRef[Soric3::Module::Irc::Connection]',
        is      => 'bare',
        default => sub { {} },
        traits  => ['Hash'],
        handles => { _connection => 'get',
                     _bind_connection => 'set',
                     _unbind_connection => 'delete',
                     enum_irc_connections => 'keys' },
    );

    method on_new_sends(Str $conn_name) {
        if ((my $conn = $self->_connection($conn_name)) {
            $conn->new_sends;
        }
    }

    method new_connection(Str :$tag, Str :$host, Num :$port = 6667,
            Str :$nickname, Str :$password = undef, Str :$username = 'soric',
            Str :$realname = 'Generic SORIC-based bot') {
        my $new_conn = Soric3::Module::Irc::Connection->new(
            tag => $tag, backref => $self);

        $self->_bind_connection($tag, $new_conn);
        $new_conn->connect($host, $port,
            { nick => $nick, user => $user, real => $real,
              password => $password });

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

class Soric3::Module::Irc::Connection
        with (Soric3::Role::Alertable, Soric3::Role::SendQueue) {
    use List::Util 'max';

    has connection => (
        is      => 'ro',
        isa     => 'AnyEvent::IRC::Client',
        default => sub { AnyEvent::IRC::Client->new },
        handles => qr/.*/,
    );

    has backref => (
        isa      => 'Soric3::Module::Irc',
        is       => 'ro',
        weak_ref => 1,
        handles  => [qw/broadcast log/],
    );

    has next_send_time => (
        isa     => 'Num',
        is      => 'rw',
        default => sub { AnyEvent->now - 10 },
    );

    has tag => (
        isa => 'Str',
        is  => 'rw',
    );

    method new_sends() {
        $self->alert if $self->is_ready;
    }

    method BUILD() {
        $self->reg_cb(
            registered => sub { shift->alert },
            connect => sub {
                my ($self, $err) = @_;
                return unless defined $err;
                $self->failed($err);

                $self->broadcast(
                    'ConnectionObserver', 'connection_state_changed',
                    $self->tag, 'failed', $err) if $self->backref;
            },
            before_irc_ping => sub {
                my ($self, $msg) = @_;

                # Prevent AnyEvent::IRC from handling the ping itself - we
                # want pongs to go through the reply scheduler
                $self->stop_event;

                # TODO make this configurable
                my $deadline = AnyEvent->now + 60;

                $self->queue_message($self->tag, [PONG => $msg->{params}->[0]],
                    sub { (AnyEvent->now >= $deadline) ? 3 : 1 });
            },
            # TODO handle connection loss, messages of all kinds
        );
    }

    method is_ready() {
        return ($self->next_send_time <= AnyEvent->now
             && $self->registered);
    }

    method _penalty(Num $adj) {
        $self->next_send_time($adj + max($self->next_send_time,
                                         AnyEvent->now - 10));
    }

    method _service() {
        my ($best_prio, $best_msg, $best_cb) = (0, undef, undef);

        $self->broadcast('Send', 'get_queued_send', $self->tag,
            sub {
                my ($prio, $msg, $cb) = @_;

                if ($prio > $best_prio) {
                    $best_prio = $prio;
                    $best_msg = $msg;
                    $best_cb = $cb;
                }
            });

        return 0 if !defined($best_msg);

        $self->log(debug => 'Sending ' . join(",", @$msg) .
                   " to " . $self->tag);
        $self->send_srv(@$msg);

        # this could retrigger us, but that's harmless
        $cb->();

        $self->_penalty(2);

        return 1;
    }

    method react() {
        return if !defined($self->backref);

        $self->_service while $self->is_ready;

        if ($self->registered && !$self->is_ready) {
            $self->alert_at($self->next_send_time);
        }
    }
}
