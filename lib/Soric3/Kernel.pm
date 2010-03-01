use MooseX::Declare;

# TODO implement role-based broadcast
# TODO We need to do something to allow modules to change their depends at
# will, especially for UI clients and configuration

# the configuration logic should be hard-coded, kept in a separate module
# with delegation... XXX investigate possible Moose models, study Kioku/DBIC

class Soric3::Kernel {
    has _modules => (
        isa     => 'HashRef[Soric3::Module]',
        traits  => ['Hash'],
        is      => 'bare',
        default => sub { {} },
        handles => { loaded_modules => 'keys',
                     modules        => 'values',
                     module_loaded  => 'exists',
                     _bind_module   => 'set',
                     module         => 'get',
                     _unload_module => 'delete' },
    );

    has client_class => (
        required => 1,
        isa      => 'Moose::Meta::Class',
        is       => 'ro', # XXX maybe this should be rw, and support dynamic
                          # munging of client classes?  I like this
    );

    # Do a postorder traversal of the module dependancy tree, instantiating and
    # binding all new modules, and removing unused ones.
    method _load_module(HashRef $used, Str $name) {
        return if $used->{$name};

        my $class_name = "Soric3::Module::" . $name;
        Class::MOP::load_class($class_name);

        $used->{$name} = 1;

        print "$class_name ", $class_name->requirements, "\n";

        # XXX we ought to be doing something dynamic here
        for my $dep ($class_name->requirements) {
            $self->_load_module($used, $dep);
        }

        return if $self->module($name);
        $self->_bind_module($name, $class_name->new(kernel => $self));
    }

    method _install_modules() {
        my %used;

        $self->_load_module(\%used, $_)
            for ($self->client_class->name->requirements);

        for my $mod ($self->loaded_modules) {
            next if $used{$mod};
            next if $mod eq 'CLIENT';

            $self->_unload_module($mod);
        }

        print "creating client...\n";
        $self->_bind_module(CLIENT =>
            $self->client_class->name->new(kernel => $self))
                unless defined $self->module('CLIENT');
    }

    method BUILD($) {
        $self->_install_modules;
    }
}
