require "crsfml"

class Game
  def mode
    @mode ||= SF::VideoMode.new(1920, 1080)
  end

  def window
    @window ||= SF::RenderWindow
      .new(mode, "orb")
      .tap { |w| w.vertical_sync_enabled = true }
      .as(SF::RenderWindow)
  end

  def process_events
    while event = window.poll_event
      case event
      when SF::Event::Closed
        window.close
      end
    end
  end

  def run
    while window.open?
      process_events

      window.clear
      window.display
    end
  end
end

module Health
  macro included
    property hp : Int32?,
             full_hp : Int32?,
             max_hp : Int32?

    def hp
      @hp ||= 100
    end

    def full_hp
      @full_hp ||= 100
    end

    def max_hp
      @max_hp ||= 100
    end
  end
end

module Position
  macro included
    property position : SF::Vector2f

    def position=(position)
      super
    end

    def position
      super
    end
  end
end

module Rotation
  macro included
    property rotation : Float32
    
    def rotation=(angle)
      super
    end

    def rotation
      super
    end
  end
end

module Velocity
  macro included
    property velocity : SF::Vector2f?

    def velocity
      @velocity ||= SF.vector2f(0.0, 0.0)
    end

    def velocity=(velocity : Tuple(Number, Number))
      @velocity = SF.vector2f(*velocity)
    end
  end
end

module Acceleration
  macro included
    property acceleration : SF::Vector2f?

    def acceleration
      @acceleration ||= SF.vector2f(0.0, 0.0)
    end

    def acceleration=(acceleration : Tuple(Number, Number))
      @acceleration = SF.vector2f(*acceleration)
    end
  end
end

class Behavior(EntityT)
  getter entity

  def initialize(entity : EntityT)
    @entity = entity
  end
  
  def update(dt)
    raise NotImplementedError
  end
end

class Movement(EntityT) < Behavior(EntityT)
  def update(dt)
    return unless can_move?
    last_velocity = entity.velocity
    entity.velocity += entity.acceleration * dt
    entity.move((last_velocity + entity.velocity) * 0.5 * dt)
  end

  private def can_move?
    entity.responds_to?(:velocity) && entity.responds_to?(:acceleration)
  end
end

class Gravity(EntityT) < Behavior(EntityT)
  def update(dt)
    entity.acceleration += {0.0, -9.8} if entity.position.y > 0
  end
end

class Entity < SF::Transformable
  property id : Int32?,
           name : String?

  def initialize(**attributes)
    super
    {% for var in @type.instance_vars %}
      if arg = attributes[:{{var.name.id}}]?
        self.{{var.name.id}} = arg
      end
    {% end %}
  end

  def name
    @name ||= "#{self.class}#{id}"
  end
end

module Behaviors(*BehaviorT)
  macro included

    macro behaviors(args, dt)
      \{% for x in args.type_vars %}
        \{% for y in x.resolve.instance.type_vars %}
          \{{y.name.stringify.split('(').first.id}}.new(self).update(dt)
        \{% end %}
      \{% end %}
    end

    def update(dt)
      behaviors(\{{Behaviors.instance}}, dt)
    end
  end
end

class Player < Entity
  include Health
  include Position
  include Rotation
  include Velocity
  include Acceleration
  include Behaviors(Gravity, Movement)
end

p1 = Player.new(
  **{
    hp: 80,
    rotation: 45.0,
    position: {200.0, 200.0},
    acceleration: {1.0, 1.0}
  }
)

p p1.name
p p1.hp
p1.rotate(10.0)
p p1.position
p p1.rotation
p p1.velocity
p p1.acceleration

puts p1
p1.update(1)

p p1.position
p p1.velocity

# p2 = Player.new
# p p2.name
# p p2.hp
# p p2.position
# p p2.rotation
# p p2.acceleration

# game = Game.new
# game.run
