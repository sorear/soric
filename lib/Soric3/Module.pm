use MooseX::Declare;

class Soric3::Module {
    # XXX do the schema here

    has kernel => (
        isa      => 'Soric3::Kernel',
        is       => 'ro',
        required => 1,
        weak_ref => 1,
    );

    method requires($class:) {
    }

    method broadcast(RoleName $obsrole, Str $method, @args) {
        return if !$self->kernel;
        for my $receiver ($self->kernel->modules) {
            next if !$receiver->does($obsrole);
            $receiver->$method(@args);
        }
    }

    method log(Str $prio, Str $text) {
        # TODO proper logging
        warn ref($self) . " - [$prio] $text\n";
    }
}
