require "chipmunk/chipmunk_crsfml"

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
  def update(dt)
    return unless movable?
    last_velocity = entity.velocity
    entity.velocity += entity.acceleration * dt
    entity.move((last_velocity + entity.velocity) * 0.5 * dt)
    entity.circle.position = entity.position
  end

  private def movable?
    entity.responds_to?(:velocity) && entity.responds_to?(:acceleration)
  end
end

class Gravity(EntityT) < Behavior(EntityT)
  property max_height : Float32,
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
    (entity.position.y + entity.circle.radius * 2)
  end

  def gravity
    @gravity ||= 1800.0
  end

  def rho
    @rho ||= 0.75 # coefficient of restitution
  end

  # TODO: take the average of entity acceleration and gravity
  def update(dt)
    if max_height < stop_height
      entity.velocity = {entity.velocity.x, 0.0_f32}
      entity.acceleration = {entity.acceleration.x, 0.0f32}
      return
    end
    if height >= 1080
      entity.position = {entity.position.x, 1080 - entity.circle.radius * 2}
      entity.velocity = {entity.velocity.x, -1 * max_velocity}
      @max_velocity *= rho
      entity.move(entity.velocity * dt)
      entity.circle.position = entity.position
    else
      entity.acceleration = {entity.acceleration.x, (entity.acceleration.y + gravity) * 0.5}
    end
    @max_height = (max_velocity * max_velocity / (gravity * 2)).as(Float32)
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
    property behaviors : Hash(Symbol, Behavior(self))?

    def behaviors
      @behaviors ||= init_behaviors
    end

    macro init_behaviors
      ({} of Symbol => Behavior(self)).tap do |b|
        \{% for klass in BehaviorT %}
          \{% kname = klass.name.split('(').first.id %}
          b[\{{kname.downcase.symbolize}}] = \{{kname}}.new(self)
        \{% end %}
      end
    end

    def update(dt)
      # behaviors.each { |_, b| b.update(dt) }
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
  include Behaviors(Movement, Gravity)

  property circle : SF::CircleShape?

  def circle
    @circle ||= SF::CircleShape.new
      .tap { |c|
        c.position = position
        c.radius = 50.0
        c.fill_color = SF::Color::White
      }.as(SF::CircleShape)
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
      .tap { |w|
        w.vertical_sync_enabled = true
        w.mouse_cursor = cursor
      }.as(SF::RenderWindow)
  end

  def cursor
    @cursor ||= SF::Cursor.new
      .tap { |c|
        c.load_from_system(SF::Cursor::Cross)
      }.as(SF::Cursor)
  end

  def debug_draw
    @debug_draw ||= SFMLDebugDraw.new(
      window,
      SF::RenderStates.new
    )
  end

  def space
    @space ||= CP::Space.new
      .tap { |s|
        @space = s
        s.gravity = gravity
        s.add(ground)
        s.add(ground2)
      }.as(CP::Space)
  end

  def gravity
    @gravity ||= CP.v(0, 800)
  end

  def ground
    @ground ||= CP::Segment.new(
      space.static_body,
      CP.v(800, 500),
      CP.v(1020, 510),
      0.0
    ).tap { |g|
      g.friction = 1.0
      g.elasticity = 1.0
    }.as(CP::Segment)
  end

  def ground2
    @ground2 ||= CP::Segment.new(
      space.static_body,
      CP.v(1080, 550),
      CP.v(1300, 530),
      0.0
    ).tap { |g|
      g.friction = 1.0
      g.elasticity = 1.0
    }.as(CP::Segment)
  end

  def mass
    1.0
  end

  def radius
    25.0
  end

  def moment
    @moment ||= CP::Circle.moment(mass, 0.0, radius)
  end

  def mouse_position
    SF::Mouse.get_position(window)
  end

  def ball_body
    CP::Body.new(mass, moment)
      .tap { |b|
        b.position = CP.v(mouse_position.x, mouse_position.y)
        space.add(b)
      }.as(CP::Body)
  end

  def ball_shape
    CP::Circle.new(ball_body, radius)
      .tap { |s|
        s.friction = 0.7
        s.elasticity = 0.8
        space.add(s)
      }.as(CP::Circle)
  end

  def ball_shapes
    @ball_shapes ||= Array(CP::Circle).new
  end

  def spawn_ball
    ball_shapes << ball_shape
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
        hp:           80,
        rotation:     45.0,
        position:     {200.0, 15.0},
        velocity:     {0.0, 0.0},
        acceleration: {0.0, 0.0},
      }
    )
  end

  def process_events
    while event = window.poll_event
      case event
      when SF::Event::Closed
        window.close
      when SF::Event::KeyPressed
        window.close if event.code == SF::Keyboard::Escape
      when SF::Event::MouseButtonPressed
        spawn_ball if event.button == SF::Mouse::Left
      end
    end
  end

  def run
    while window.open?
      process_events

      @accumulator += frame_time

      while accumulator >= dt
        space.step(dt)
        # player.update(dt)

        @accumulator -= dt
        @t += dt
      end

      window.clear
      # window.draw(player)

      puts "balls: #{ball_shapes.size}"

      ball_shapes
        .reject! { |ball_shape|
          ball_body = ball_shape.body.not_nil!
          ball_body.position.y > 1080 && space.remove(ball_shape, ball_body).nil?
        }.each { |ball_shape|
          ball_body = ball_shape.body.not_nil!
          debug_draw.draw_circle(
            CP.v(ball_body.position.x, ball_body.position.y),
            ball_body.angle,
            radius,
            SFMLDebugDraw::Color.new(0.0, 1.0, 0.0),
            SFMLDebugDraw::Color.new(0.0, 0.0, 0.0)
          )
        }

      debug_draw.draw_segment(ground.a, ground.b, SFMLDebugDraw::Color.new(1.0, 0.0, 0.0))
      debug_draw.draw_segment(ground2.a, ground2.b, SFMLDebugDraw::Color.new(1.0, 0.0, 0.0))
      window.display
    end
  end
end

game = Game.new
game.run
