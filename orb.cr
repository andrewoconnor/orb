require "crsfml"

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

abstract class Behavior(EntityT)
  getter entity

  def initialize(entity : EntityT)
    @entity = entity
  end
  
  abstract def update(dt)
end

class Movement(EntityT) < Behavior(EntityT)
  # def update(dt)
  #   return unless can_move?
  #   last_velocity = entity.velocity
  #   entity.velocity += entity.acceleration * dt
  #   entity.move((last_velocity + entity.velocity) * 0.5 * dt)
  #   entity.circle.position = entity.position
  # end

  def update(dt)
    return unless can_move?
    last_velocity = entity.velocity
    entity.velocity += entity.acceleration * dt
    old_position = entity.position
    entity.move((last_velocity + entity.velocity) * 0.5 * dt)
    if (entity.position.y + entity.circle.radius) * -1 + 1080 < entity.circle.radius
      entity.behaviors.each { |b| b.free_fall = false if b.responds_to?(:free_fall) }
      entity.position = {old_position.x, entity.circle.radius * -2 + 1080}
    end
    entity.circle.position = entity.position
  end

  private def can_move?
    entity.responds_to?(:velocity) && entity.responds_to?(:acceleration)
  end
end

class Gravity(EntityT) < Behavior(EntityT)

  property max_height : Float32,
           free_fall : Bool,
           max_velocity : Float32

  def initialize(entity : EntityT)
    super
    @max_height = height
    @max_velocity = Math.sqrt(2 * max_height * gravity)
    @free_fall = true
  end

  def stop_height
    @stop_height ||= 0.1
  end

  def height
    (entity.position.y + entity.circle.radius) * -1 + 1080
  end

  def gravity
    @gravity ||= 1000.0
  end

  def rho
    @rho ||= 0.75 # coefficient of restitution
  end

  # TODO: take the average of entity acceleration and gravity
  def update(dt)
    if max_height < stop_height
      entity.velocity = {entity.velocity.x, 0.0_f32}
      return
    end
    if free_fall
      if height < entity.circle.radius
        @free_fall = false
      else
        # entity.velocity = {entity.velocity.x, entity.velocity.y + gravity * dt}
        entity.acceleration = {entity.acceleration.x, (entity.acceleration.y + gravity) * 0.5}
      end
    else
      @max_velocity *= rho
      entity.velocity = {entity.velocity.x, -1 * max_velocity}
      @free_fall = true
    end
    @max_height = (max_velocity * max_velocity / (gravity * 2)).as(Float32)
  end
  # def update(dt)
  #   if max_height < stop_height
  #     entity.velocity = {entity.velocity.x, 0.0_f32}
  #     return
  #   end
  #   if free_fall
  #     if height < entity.circle.radius
  #       @free_fall = false
  #     else
  #       entity.velocity = {entity.velocity.x, entity.velocity.y + gravity * dt}
  #     end
  #   else
  #     @max_velocity *= rho
  #     entity.velocity = {entity.velocity.x, -1 * max_velocity}
  #     @free_fall = true
  #   end
  #   @max_height = (max_velocity * max_velocity / (gravity * 2)).as(Float32)
  # end
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
    property behaviors : Array(Behavior(self))?

    def behaviors
      @behaviors ||= init_behaviors
    end

    macro init_behaviors
      ([] of Behavior(self)).tap do |b|
        \{% for klass in BehaviorT %}
           b << \{{klass.name.split('(').first.id}}.new(self)
        \{% end %}
      end
    end

    def update(dt)
      behaviors.each { |b| b.update(dt) }
    end
  end
end

class Player < Entity
  include SF::Drawable
  include Health
  include Position
  include Rotation
  include Velocity
  include Acceleration
  include Behaviors(Gravity, Movement)

  property circle : SF::CircleShape?

  def circle
    @circle ||= SF::CircleShape.new.tap do |c|
      c.position = position
      c.radius = 50
      c.fill_color = SF::Color::White
    end.as(SF::CircleShape)
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    target.draw(circle, states)
  end
end

class Game
  property t : Float32,
           accumulator : Float32

  def initialize
    @t = 0.0_f32
    @accumulator = 0.0_f32
  end

  def mode
    @mode ||= SF::VideoMode.new(1920, 1080)
  end

  def window
    @window ||= SF::RenderWindow
      .new(mode, "orb")
      .tap { |w| w.vertical_sync_enabled = true }
      .as(SF::RenderWindow)
  end

  def clock
    @clock ||= SF::Clock.new
  end

  def dt
    @dt ||= 0.01
  end

  def frame_time
    clock.restart.as_seconds
  end

  def player
    @player ||= Player.new(
      **{
        hp: 80,
        rotation: 45.0,
        position: {200.0, 200.0},
        velocity: {0.0, 0.0},
        acceleration: {0.0, 0.0}
      }
    )
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

      @accumulator += frame_time

      while accumulator >= dt
        player.update(dt)

        @accumulator -= dt;
        @t += dt;
      end

      window.clear
      window.draw(player)
      window.display
    end
  end
end

game = Game.new
game.run
