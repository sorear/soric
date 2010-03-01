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

    method sends_changed(Str $conn_name) {
        if ((my $conn = $self->_connection($conn_name)) {
            $conn->sends_changed;
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

        $self->broadcast('ConnectionObserver', 'connection_status_changed',
            $tag);
    }

    method delete_connection(Str $tag, Str $reason) {
        my $conn = $self->_connection($tag);

        $conn->send_srv(QUIT => $reason) if $conn->registered;
        $conn->disconnect($reason);

        $self->_unbind_connection($tag);
        $self->broadcast('ConnectionObserver', 'connection_status_changed',
            $tag);
    }
}

class Soric3::Module::Irc::Connection
        with (Soric3::Role::AlertAt, Soric3::Role::SendQueue) {
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

    has error => (
        isa       => 'Any',
        predicate => 'failed',
        is        => 'rw',
    );

    method BUILD() {
        $self->reg_cb(
            registered => sub { shift->alert },
            connect => sub {
                my ($self, $err) = @_;
                return unless defined $err;
                $self->error($err);

                $self->broadcast(
                    'ConnectionObserver', 'connection_status_changed',
                    $self->tag) if $self->backref;
            },
            before_irc_ping => sub {
                my ($self, $msg) = @_;

                # Prevent AnyEvent::IRC from handling the ping itself - we
                # want pongs to go through the reply scheduler
                $self->stop_event;

                # TODO make this configurable
                my $deadline = AnyEvent->now + 60;

                $self->queue_message($self->tag, [PONG => $msg->{params}->[0]],
                    sub { (AnyEvent->now >= $deadline) ? 'urgent' : 'daemon' });
            },
            # TODO handle connection loss, messages of all kinds
        );
    }

    method new_sends() {
        $self->_service;
    }

    method is_ready() {
        return ($self->next_send_time <= AnyEvent->now
             && $self->registered);
    }

    method _penalty(Num $adj) {
        $self->next_send_time($adj + max($self->next_send_time,
                                         AnyEvent->now - 10));
    }

    method _service_once() {
        my ($best_prio, $best_msg, $best_cb) = (0, undef, undef);

        $self->broadcast('Send', 'get_queued_send', $self->tag,
            sub {
                my ($prio, $msg, $cb) = @_;

                $prio = ({ daemon => 1, user => 2, urgent => 3})->{$prio};

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

    method alert() {
        return if !defined($self->backref);
        $self->cancel_alert;

        while ($self->is_ready) {
            $self->_service_once || return;
        }

        if ($self->registered) {
            $self->alert_at($self->next_send_time);
        }
    }
}
