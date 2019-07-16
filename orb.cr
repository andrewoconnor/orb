require "chipmunk/chipmunk_crsfml"
require "../crimgui/src/crimgui/imgui"

module Health
  macro included
    property hp : Int32 = 100
    property full_hp : Int32 = 100
    property max_hp : Int32 = 100
  end
end

class HealthProperty
  include Health
end

module Position
  macro included
    property position : SF::Vector2f = SF.vector2f(0.0, 0.0)

    def position=(position)
      super
    end

    def position
      super
    end
  end
end

class PositionProperty
  include Position
end

module Rotation
  macro included
    property rotation : Float32 = 0.0f32

    def rotation=(angle)
      super
    end

    def rotation
      super
    end
  end
end

class RotationProperty
  include Rotation
end

module Velocity
  macro included
    property velocity : SF::Vector2f = SF.vector2f(0.0, 0.0)

    def velocity=(velocity : Tuple(Float32, Float32))
      @velocity = SF.vector2f(*velocity)
    end

    def velocity=(velocity : SF::Vector2f)
      @velocity = velocity
    end
  end
end

class VelocityProperty
  include Velocity
end

module Acceleration
  macro included
    property acceleration : SF::Vector2f = SF.vector2f(0.0, 0.0)

    def acceleration=(acceleration : Tuple(Float32, Float32))
      @acceleration = SF.vector2f(*acceleration)
    end

    def acceleration=(acceleration : SF::Vector2f)
      @acceleration = acceleration
    end
  end
end

class AccelerationProperty
  include Acceleration
end

module Properties(*PropertyT)
  macro included
    alias PropertyTypes = Pointer(Void) | Int32.class | Float32.class | SF::Vector2f.class
    property properties : Hash(Symbol, Hash(Symbol, Pointer(Void)))?
    property property_types : Hash(Symbol, PropertyTypes)?

    \{% for klass in PropertyT %}
      include \{{klass}}
    \{% end %}

    def properties
      @properties ||= init_properties
    end

    def property_types
      @property_types ||= init_property_types
    end

    macro klass_props(klass)
      ({} of Symbol => Hash(Symbol, Pointer(Void))).tap do |props|
        \{% for ivar in klass.resolve.instance_vars %}
          props[\{{ivar.symbolize}}] ||= {} of Symbol => Pointer(Void)
          props[\{{ivar.symbolize}}][:get] = Box.box(-> { self.\{{ivar.id}} })
          props[\{{ivar.symbolize}}][:set] = Box.box(-> (val : \{{ivar.type}}) { self.\{{ivar.id}} = val })
        \{% end %}
      end
    end

    macro init_properties
      ({} of Symbol => Hash(Symbol, Pointer(Void))).tap do |props|
        \{% for klass in PropertyT %}
          props.merge! klass_props(\{{"#{klass}Property".id}})
        \{% end %}
      end
    end

    macro klass_prop_types(klass)
      ({} of Symbol => PropertyTypes).tap do |types|
        \{% for ivar in klass.resolve.instance_vars %}
          types[\{{ivar.symbolize}}] = \{{ivar.type}}
        \{% end %}
      end
    end

    macro init_property_types
      ({} of Symbol => PropertyTypes).tap do |types|
        \{% for klass in PropertyT %}
          types.merge! klass_prop_types(\{{"#{klass}Property".id}})
        \{% end %}
      end
    end
  end
end

# module Texture
#   macro included
#     property texture : SF::Texture?,
#       sprite : SF::Sprite?

#     def texture
#       @texture ||= SF::Texture.new(640, 480)
#     end

#     def texture=(file)
#       @texture = SF::Texture.from_file(file)
#     end

#     def sprite
#       @sprite ||= SF::Sprite.new(texture)
#     end
#   end
# end

class Entity < SF::Transformable
  property id : Int32?
  property name : String?
  property context : Game

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

abstract class Behavior(Entity)
  getter entity

  def initialize(entity : Entity)
    @entity = entity
  end

  abstract def update(dt)
end

class FaceMouse(Entity) < Behavior(Entity)
  def context
    entity.context
  end

  def window
    context.window.not_nil!
  end

  def body
    entity.drawables[:body].as(SF::CircleShape)
  end

  def sprite
    entity.drawables[:sprite].as(SF::Sprite)
  end

  def radius
    body.radius
  end

  def crosshair
    SF::Mouse.get_position(window)
  end

  def center
    entity.position
  end

  def angle
    Math.atan2(crosshair.y - center.y, crosshair.x - center.x)
  end

  def degrees
    angle * 180.0 / Math::PI + (angle < 0 ? 360 : 0)
  end

  def edge
    center + SF.vector2f(Math.cos(angle), Math.sin(angle)) * radius
  end

  def update(dt)
    return if context.show_debug_menu?
    entity.rotate(degrees - entity.rotation)
    sprite.rotation = entity.rotation
    entity.drawables[:face] = SF::VertexArray.new(SF::Lines, 2).tap { |v|
      v[0] = SF::Vertex.new(center, SF::Color::Green)
      v[1] = SF::Vertex.new(edge, SF::Color::Green)
    }.as(SF::VertexArray)
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
      behaviors.each { |_, b| b.update(dt) }
    end
  end
end

module Drawable
  macro included
    include SF::Drawable

    property drawables : Hash(Symbol, SF::Drawable) = {} of Symbol => SF::Drawable

    def draw(target : SF::RenderTarget, states : SF::RenderStates)
      drawables.each do |_, drawable|
        drawable.position = self.position if drawable.responds_to?(:position=)
        target.draw(drawable, states)
      end
    end
  end
end

class Player < Entity
  include Drawable
  include Properties(Health, Rotation, Position, Velocity, Acceleration)
  include Behaviors(FaceMouse)
end

class SpriteSheet
  property files : Array(String)
  property texture : SF::Texture?

  def initialize(files)
    @files = files
  end

  def texture_size
    @texture_size ||= SF::Texture.from_file(files.first).size.as(SF::Vector2i)
  end

  def sheet_size
    @sheet_size ||= SF.vector2i(texture_size.x * files.size, texture_size.y)
  end

  def sprite(file, offset)
    SF::Sprite.new(SF::Texture.from_file(file)).tap do |s|
      s.position = SF.vector2f(offset, 0)
    end
  end

  def texture
    @texture ||= SF::RenderTexture.new(sheet_size.x, sheet_size.y, false).tap { |sheet|
      sheet.clear
      files.each_with_index { |file, i|
        sheet.draw(sprite(file, texture_size.x * i))
      }
      sheet.display
    }.texture
  end
end

class Animation
  include SF::Drawable

  property sprite_sheet : SpriteSheet
  property duration : Float32
  property t : Float32 = 0.0f32
  property curr_frame : Int32 = 0
  property sprite : SF::Sprite
  property? paused : Bool = false

  def initialize(sprite_sheet, duration)
    @sprite_sheet = sprite_sheet
    @t = 0.0_f32
    @duration = duration
    @curr_frame = 0
    @sprite = SF::Sprite.new(texture, texture_rect)
    @paused = false
  end

  def num_frames
    @num_frames ||= (sprite_sheet.files.size).as(Int32)
  end

  def frame_length
    @frame_length ||= (duration / num_frames).as(Float32)
  end

  def texture_size
    sprite_sheet.texture_size
  end

  def texture
    sprite_sheet.texture
  end

  def texture_rect
    SF.int_rect(texture_size.x * curr_frame, 0, texture_size.x, texture_size.y)
  end

  def next_frame?
    !paused? && @t >= frame_length
  end

  def update(dt)
    @t += dt
    return unless next_frame?
    @t = 0.0_f32
    @curr_frame = curr_frame >= (num_frames - 1) ? 0 : curr_frame + 1
    @sprite.tap { |s|
      s.texture_rect = texture_rect
      s.position = SF.vector2f(100.0, 100.0)
    }
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    target.draw(sprite, states)
  end
end

class Game
  property t : Float32 = 0.0f32
  property accumulator : Float32 = 0.0f32
  property? show_debug_menu : Bool = false

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

  def render_states
    @render_states ||= SF::RenderStates.new
  end

  def screen
    @screen ||= render_states.transform
      .transform_rect(SF.float_rect(0, 0, 1, 1))
      .as(SF::FloatRect)
  end

  def scale
    @scale ||= (-2 / (screen.width + screen.height)).as(Float32)
  end

  def debug_draw
    @debug_draw ||= SFMLDebugDraw.new(
      window,
      render_states
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

  def imgui
    @imgui ||= ImGui.new(window).tap { |i|
      i.font_atlas_clear
      i.add_font_from_file_ttf("/Library/Fonts/Andale Mono.ttf", 24.0)
      i.update_font_texture
    }.as(ImGui)
  end

  def player
    @player ||= Player.new(
      **{
        context:      self,
        hp:           80,
        rotation:     90.0,
        position:     {1000.0, 500.0},
        velocity:     {0.0f32, 0.0f32},
        acceleration: {0.0f32, 0.0f32},
        drawables:    {
          :body => SF::CircleShape.new.tap { |c|
            c.position = {1000.0, 500.0}
            c.radius = 25.0
            c.origin = {25.0, 25.0}
            c.fill_color = SF::Color::Black
            c.outline_color = SF::Color::Green
            c.outline_thickness = scale * 1.25
          },
          :sprite => SF::Sprite.new(
            SF::Texture.from_file("assets/textures/player/shotgun/idle/survivor-idle_shotgun_0.png")
          ).tap { |s|
            s.origin = {100.0, 120.0}
          },
        } of Symbol => SF::Drawable,
      }
    )
  end

  def process_events
    while event = window.poll_event
      imgui.process_event(event)
      case event
      when SF::Event::Closed
        window.close
      when SF::Event::KeyPressed
        case event.code
        when SF::Keyboard::Escape
          window.close
        when SF::Keyboard::Hyphen # osx for tilde
          @show_debug_menu = !show_debug_menu?
        end
        # when SF::Event::MouseButtonPressed
        #   spawn_ball if event.button == SF::Mouse::Left && !show_debug_menu
      end
    end
  end

  def reload_files
    (0..19).to_a.map_with_index do |i|
      "assets/textures/player/shotgun/reload/survivor-reload_shotgun_#{i}.png"
    end
  end

  def reload_sprite_sheet
    @reload_sprite_sheet ||= SpriteSheet.new(reload_files)
  end

  def reload_animation
    @reload_animation ||= Animation.new(reload_sprite_sheet, 2.0_f32)
  end

  def debug_menu
    imgui.set_next_window_size(ImVec2.new(430, 450), LibImGui::ImGuiCond::FirstUseEver)
    if !imgui.begin("Property editor")
      imgui.end
      return
    end
    imgui.push_style_var(LibImGui::ImGuiStyleVar::FramePadding, ImVec2.new(2, 2))
    imgui.push_id(99999)
    imgui.align_text_to_frame_padding
    node_open = imgui.tree_node("Player1", "Player1")
    imgui.separator
    imgui.columns(2)
    imgui.next_column
    imgui.next_column
    prop_flags = LibImGui::ImGuiTreeNodeFlags::Leaf | LibImGui::ImGuiTreeNodeFlags::NoTreePushOnOpen | LibImGui::ImGuiTreeNodeFlags::Bullet
    if node_open
      player.properties.each_with_index(1) do |(prop, callbacks), idx|
        imgui.push_id(99999 - idx)
        imgui.align_text_to_frame_padding
        imgui.tree_node_ex(prop.to_s, prop_flags, prop.to_s)
        imgui.next_column
        if player.property_types[prop] == Int32
          int_val = Box(Proc(Int32)).unbox(callbacks[:get]).call
          int_ptr = pointerof(int_val)
          if imgui.input_int("###{prop}_int", int_ptr, 1, 10)
            Box(Proc(Int32, Int32)).unbox(callbacks[:set]).call(int_ptr.value)
          end
        elsif player.property_types[prop] == Float32
          float_val = Box(Proc(Float32)).unbox(callbacks[:get]).call
          float_ptr = pointerof(float_val)
          if imgui.input_float("###{prop}_float", float_ptr, 0.1, 1.0, "%.1f")
            Box(Proc(Float32, Float32)).unbox(callbacks[:set]).call(float_ptr.value)
          end
        elsif player.property_types[prop] == SF::Vector2f
          vec2f_val = Box(Proc(SF::Vector2f)).unbox(callbacks[:get]).call
          fx = vec2f_val.x
          fy = vec2f_val.y
          fx_ptr = pointerof(fx)
          fy_ptr = pointerof(fy)
          if imgui.input_float("x###{prop}_float", fx_ptr, 0.1, 1.0, "%.1f")
            new_vec = SF.vector2f(fx_ptr.value, fy)
            Box(Proc(SF::Vector2f, SF::Vector2f)).unbox(callbacks[:set]).call(new_vec)
          end
          imgui.next_column
          imgui.next_column
          if imgui.input_float("y###{prop}_float", fy_ptr, 0.1, 1.0, "%.1f")
            new_vec = SF.vector2f(fx, fy_ptr.value)
            Box(Proc(SF::Vector2f, SF::Vector2f)).unbox(callbacks[:set]).call(new_vec)
          end
        end
        imgui.next_column
        imgui.pop_id
      end
      imgui.tree_pop
    end
    imgui.pop_id
    imgui.pop_style_var
    imgui.end
  end

  def run
    while window.open?
      process_events

      frame_time.tap do |ft|
        @accumulator += ft
        imgui.update(ft) # don't handle events in fixed step
      end

      while accumulator >= dt
        space.step(dt)
        player.update(dt)
        reload_animation.update(dt)

        @accumulator -= dt
        @t += dt
      end

      window.clear
      # window.draw(player)

      # window.draw(reload_animation)

      # ball_shapes
      #   .reject! { |ball_shape|
      #     ball_body = ball_shape.body.not_nil!
      #     ball_body.position.y > 1080 && space.remove(ball_shape, ball_body).nil?
      #   }.each { |ball_shape|
      #     ball_body = ball_shape.body.not_nil!
      #     debug_draw.draw_circle(
      #       CP.v(ball_body.position.x, ball_body.position.y),
      #       ball_body.angle,
      #       radius,
      #       SFMLDebugDraw::Color.new(0.0, 1.0, 0.0),
      #       SFMLDebugDraw::Color.new(0.0, 0.0, 0.0)
      #     )
      #   }

      # debug_draw.draw_segment(ground.a, ground.b, SFMLDebugDraw::Color.new(1.0, 0.0, 0.0))
      # debug_draw.draw_segment(ground2.a, ground2.b, SFMLDebugDraw::Color.new(1.0, 0.0, 0.0))

      imgui.new_frame
      debug_menu if show_debug_menu?
      imgui.show_demo_window
      imgui.end_frame
      imgui.render
      window.draw(imgui)

      window.display
    end
  end
end

game = Game.new
game.run
