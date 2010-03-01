use MooseX::Declare;

class Soric3::Module {
    # XXX do the schema here

    has kernel => (
        isa      => 'Soric3::Kernel',
        is       => 'ro',
        required => 1,
        weak_ref => 1,
        handles  => ['module'],
    );

    method requirements($class:) {
        return ();
    }

    method broadcast(Str $obsrole, Str $method, @args) {
        return if !$self->kernel;
        for my $receiver ($self->kernel->modules) {
            next if !$receiver->does('Soric3::Role::' . $obsrole);
            $receiver->$method(@args);
        }
    }

    method log(Str $prio, Str $text) {
        # TODO proper logging
        my ($cap) = (ref($self) =~ /.*::(.*)/);
        print STDERR $cap . " - [" . substr($prio,0,2) . "] $text\n";
    }
}
