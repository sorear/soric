use MooseX::Declare;

role Soric3::Role::AlertAt {
    use AnyEvent;
    use Scalar::Util 'weaken';

    has _timer => (
        is       => 'rw',
        isa      => 'Maybe[Ref]',
        init_arg => undef,
    );

    method alert_at(Num $when) {
        my $weak_self = $self;
        weaken $weak_self;

        $self->_timer(AE::timer($when - AE::now(), 0, sub {
            return if !defined($weak_self);
            $weak_self->_timer(undef);
            $weak_self->alert;
        }));
    }

    method cancel_alert() {
        $self->_timer(undef);
    }
}
