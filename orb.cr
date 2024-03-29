require "json"

require "chipmunk/chipmunk_crsfml"
require "../crimgui/src/crimgui/imgui"

enum GameState
  Intro
  Loading
  MainMenu
  Active
  Paused
end

@[Flags]
enum EntityState
  Idle
  Move
  Melee
  Shoot
  Dead
end

@[Flags]
enum ItemSlotType
  LeftHand
  RightHand
end

annotation ImguiIgnore
end

module AnimationConverter
  @@entity = Entity.new
  @@sprite_sheets = {} of Int32 => SpriteSheet

  def self.init(@@entity : Entity, @@sprite_sheets : Hash(Int32, SpriteSheet))
    self
  end

  def self.from_json(pull : JSON::PullParser)
    ({} of String => Animation).tap do |animations|
      pull.read_array do
        anim_id = 0
        anim_name = "Unnamed"
        duration = 0.5f32
        origin = {100.0f32, 100.0f32}
        loop = false
        pull.read_object do |anim_key|
          case anim_key
          when "id"
            anim_id = pull.read_string.to_i
          when "attributes"
            pull.read_object do |attr_key|
              case attr_key
              when "name"
                anim_name = pull.read_string
              when "duration"
                duration = pull.read_float.to_f32
              when "origin"
                pull.read_array do
                  origin = {pull.read_float.to_f32, pull.read_float.to_f32}
                end
              when "loop"
                loop = pull.read_bool
              end
            end
          when "relationships"
            pull.read_object do |rel_key|
              if rel_key == "sprite_sheet"
                pull.read_object do |sheet_key|
                  if sheet_key == "data"
                    pull.read_object do |data_key|
                      if data_key == "id"
                        sheet_id = pull.read_string.to_i
                        if @@sprite_sheets[sheet_id]?
                          animations[anim_name] = Animation.new(
                            anim_id,
                            anim_name,
                            @@entity,
                            @@sprite_sheets[sheet_id],
                            duration,
                            origin,
                            loop
                          )
                        else
                          raise "Failed to find sprite sheet: #{sheet_id}"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

class AnimationData
  include JSON::Serializable

  @@entity = Entity.new
  @@sprite_sheets = {} of Int32 => SpriteSheet

  @[JSON::Field(key: "data", converter: AnimationConverter.init(@@entity, @@sprite_sheets))]
  property animations : Hash(String, Animation)

  def self.init(@@entity : Entity, @@sprite_sheets : Hash(Int32, SpriteSheet))
    self
  end
end

module SpriteSheetConverter
  def self.from_json(pull : JSON::PullParser)
    ({} of Int32 => SpriteSheet).tap do |sprite_sheets|
      pull.read_array do
        sheet_id = 0
        pull.read_object do |sheet_key|
          case sheet_key
          when "id"
            sheet_id = pull.read_string.to_i
          when "attributes"
            pull.read_object do |attr_key|
              if attr_key == "path"
                pull.read_string.tap do |path|
                  puts path
                  sprite_sheets[sheet_id] = SpriteSheet.new(sheet_id, path)
                end
              end
            end
          end
        end
      end
    end
  end
end

class SpriteSheetData
  include JSON::Serializable

  @[JSON::Field(key: "data", converter: SpriteSheetConverter)]
  property sprite_sheets : Hash(Int32, SpriteSheet)
end

module States
  macro included
    property states : EntityState = EntityState::Idle
  end
end

module Drawables
  macro included
    property drawables : Hash(Symbol, SF::Drawable) = {} of Symbol => SF::Drawable
  end
end

module Health
  macro included
    property hp : Int32 = 100
    property full_hp : Int32 = 100
    property max_hp : Int32 = 100
    property? invulnerable : Bool = false

    def dead?
      invulnerable? ? false : hp <= 0
    end
  end
end

module Position
  macro included
    property position : SF::Vector2f = SF.vector2f(0.0, 0.0)

    def position=(position : Tuple(Float32, Float32))
      super(SF.vector2f(*position))
    end

    def position=(position : SF::Vector2f)
      super
    end

    def position
      super
    end
  end
end

module Rotation
  macro included
    property rotation : Float32 = 0.0f32

    def rotation=(angle : Float32)
      super
    end

    def rotation
      super
    end
  end
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

module Inventory
  macro included
    property inventory : Hash(Int32, Item) = {} of Int32 => Item
  end
end

module EquippedItems
  macro included
    property equipped_items : Hash(ItemSlotType, Item) = {} of ItemSlotType => Item
  end
end

module ItemSlot
  macro included
    property item_slot_type : ItemSlotType = ItemSlotType::None

    def equip(equipper : EquippedItems)
      item_slot_type
        .each do |slot|
          equipper.as(EquippedItems).equipped_items[slot] = self if self.is_a?(Item)
        end
    end

    def unequip(equipper : EquippedItems)
      item_slot_type
        .each do |slot|
          equipper.as(EquippedItems).equipped_items.delete(slot)
        end
    end
  end
end

module Owner
  macro included
    property owner : Entity?

    def own(new_owner : Entity, context : Game)
      @owner = new_owner
      self.context = context
    end

    def disown!
      if self.is_a?(ItemSlot) && owner.is_a?(EquippedItems)
        self.as(ItemSlot).unequip(owner.as(EquippedItems)) if owner
      end
      @owner = nil
    end
  end
end

macro define_property_class(klass)
  class {{ "#{klass}Property".id }}
    include {{klass}}
  end
end

module Properties(*PropertyT)
  macro included
    {% if !@type.has_constant?(:PROPERTY_TYPES) %}
      PROPERTY_TYPES = {} of Nil => Nil
    {% end %}

    macro klass_properties(klass)
      \{% for ivar in klass.resolve.instance_vars %}
        \{% PROPERTY_TYPES[ivar.symbolize] = ivar.type unless ivar.annotation(ImguiIgnore) %}
      \{% end %}
    end

    macro register_properties
      \{% for klass in PropertyT %}
        klass_properties(\{{"#{klass}Property".id}})
      \{% end %}
    end

    {% for klass in PropertyT %}
      define_property_class({{klass}})
      include {{klass}}
    {% end %}

    include PropertyUI
  end
end

module PropertyUI
  def imgui
    @imgui ||= context.imgui.as(ImGui)
  end

  def node_flags
    LibImGui::ImGuiTreeNodeFlags::Leaf | LibImGui::ImGuiTreeNodeFlags::NoTreePushOnOpen | LibImGui::ImGuiTreeNodeFlags::Bullet
  end

  macro property_nodes(name)
    {% for k, v in PROPERTY_TYPES %}
      imgui.align_text_to_frame_padding
      imgui.tree_node_ex({{k}}.to_s, node_flags, {{k}}.to_s)
      val = self.{{k.id}}{{(v == Bool ? "?" : "").id}}
      if val.is_a?(Hash(Symbol, SF::Drawable))
        imgui.columns(1)
      else
        imgui.columns(2)
      end
      imgui.next_column
      prop_input({{k}}, val) do |new_val|
        self.{{k.id}} = new_val.as({{v}}) unless new_val.nil?
      end
      imgui.next_column
    {% end %}
  end

  def prop_input(prop, val : T, &block) forall T
    case val
    when Int32
      int_val = val.as(Int32)
      if imgui.input_int("###{prop}_int", pointerof(int_val), 1, 10)
        yield int_val
      end
    when Float32
      float_val = val.as(Float32)
      if imgui.input_float("###{prop}_float", pointerof(float_val), 0.1, 1.0, "%.1f")
        yield float_val
      end
    when Bool
      bool_val = val.as(Bool)
      if imgui.checkbox("###{prop}_bool", pointerof(bool_val))
        yield bool_val
      end
    when SF::Vector2f
      x = val.x.as(Float32)
      y = val.y.as(Float32)
      if imgui.input_float("x###{prop}_float", pointerof(x), 0.1, 1.0, "%.1f")
        yield SF.vector2f(x, y)
      end
      imgui.next_column
      imgui.next_column
      if imgui.input_float("y###{prop}_float", pointerof(y), 0.1, 1.0, "%.1f")
        yield SF.vector2f(x, y)
      end
    when Hash(Int32, Item)
      if imgui.begin_menu("items")
        Item.all_items.each do |item|
          give_item = item.owner == self
          if imgui.checkbox("#{item}", pointerof(give_item))
            if give_item
              item.own(self, context)
              val[item.id] = item
            else
              val.delete(item.id)
              item.disown!
            end
          end
        end
        imgui.end_menu
      end
      yield val
    when Hash(ItemSlotType, Item)
      ItemSlotType.values.each do |slot|
        pos = (inventory.values.index(equipped_items[slot]?) || -1) + 1
        if imgui.combo("#{slot}", pointerof(pos), inventory.values.map(&.to_s).unshift(""))
          item = inventory.values[pos - 1]?
          if pos == 0 && equipped_items.has_key?(slot)
            equipped_items[slot].as(ItemSlot).unequip(self)
          elsif item && item.is_a?(ItemSlot)
            item.as(ItemSlot).equip(self)
          end
        end
      end
      yield val
    when Hash(Symbol, SF::Drawable)
      animations = context.animations
      anim_keys = animations.keys
      anim_id = Animation.selected_debug_anim
      if imgui.combo("Drawables", pointerof(anim_id), anim_keys.unshift(""))
        Animation.selected_debug_anim = anim_id
      end
      animation = animations[anim_keys[anim_id]]?
      if animation && animation.is_a?(Animation)
        imgui.draw_animation(animation.as(Animation))
      end
      yield val
    end
  end

  def property_tree
    node_open = imgui.tree_node(name, name)
    imgui.separator
    imgui.columns(2)
    imgui.next_column
    imgui.next_column
    if node_open
      property_nodes(name)
      imgui.tree_pop
    end
    imgui.columns(1)
  end
end

class Entity < SF::Transformable
  property id : Int32 = 0
  property context : Game

  def initialize(**attributes)
    super()
    {% for var in @type.instance_vars %}
      if arg = attributes[:{{var.id}}]?
        self.{{var.id}} = arg
      end
    {% end %}
    {% if @type.has_constant?(:PROPERTY_TYPES) %}
      register_properties
    {% end %}
  end

  def context=(game : Game)
    return if context == game
    @context = game
    game.entity_count = game.entity_count + 1
    @id = game.entity_count
  end

  def name
    "#{self.class}#{id}"
  end
end

class Item < Entity
  ALL_ITEMS = [] of Item

  include Properties(Owner)

  def self.all_items
    return ALL_ITEMS unless ALL_ITEMS.empty?
    {% for item in @type.all_subclasses.reject(&.abstract?) %}
      ALL_ITEMS << {{"#{item}.new".id}}
    {% end %}
    ALL_ITEMS
  end
end

class Bullet < Entity
  include Properties(Rotation, Position, Velocity, Acceleration)
end

abstract class Weapon < Item
  include Properties(ItemSlot)

  abstract def primary_attack
  abstract def melee_attack
end

module Ammo
  macro included
    property bullets_in_mag : Int32 = 0
    property mag_capacity : Int32 = 0
    property max_carry : Int32 = 0
    property bullet_velocity : SF::Vector2f = SF.vector2f(0.0, 0.0)
    property spread : Float32 = 0.0f32
  end
end

abstract class Gun < Weapon
  abstract def primary_attack
  abstract def melee_attack
  abstract def reload
end

class Handgun < Gun
  def item_slot_type
    ItemSlotType::LeftHand | ItemSlotType::RightHand
  end

  def primary_attack
  end

  def melee_attack
  end

  def reload
  end
end

class Shotgun < Gun
  def item_slot_type
    ItemSlotType::LeftHand | ItemSlotType::RightHand
  end

  def primary_attack
  end

  def melee_attack
  end

  def reload
  end
end

class Rifle < Gun
  def item_slot_type
    ItemSlotType::LeftHand | ItemSlotType::RightHand
  end

  def primary_attack
  end

  def melee_attack
  end

  def reload
  end
end

abstract class OrbProcess
  property? finished : Bool = false

  abstract def update(dt)
end

# does nothing
class SleepProcess < OrbProcess
  property timer : Float32 = 0.0f32
  property duration : Float32

  def initialize(@duration)
  end

  def update(dt)
    @timer += dt
    @finished = true if timer >= duration
  end
end

# single frame process
class GenericProcess < OrbProcess
  def on_update(&block)
    @on_update_callback = block
  end

  def update(dt)
    if callback = @on_update_callback
      callback.call
    end
    @finished = true
  end
end

class ProcessBuffer
  property buffer : Deque(OrbProcess)?

  def buffer
    @buffer ||= Deque(OrbProcess).new
  end

  def <<(process)
    buffer << process
  end

  def update(dt)
    if process = buffer.first?
      process.update(dt)
      buffer.shift if process.finished?
    end
  end
end

abstract class Behavior(Entity)
  getter entity

  def initialize(@entity : Entity)
  end

  abstract def update(dt)
end

class FaceMouse(Entity) < Behavior(Entity)
  def context
    entity.context
  end

  def window
    context.window
  end

  def body
    entity.drawables[:body].as(SF::CircleShape)
  end

  def sprite
    s = entity.drawables[:current_sprite]
    s.is_a?(Animation) ? s.sprite.as(SF::Sprite) : SF::Sprite.new
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
    entity.rotate(degrees - entity.rotation) unless context.show_debug_menu?
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

    def draw(target : SF::RenderTarget, states : SF::RenderStates)
      drawables.each do |_, drawable|
        target.draw(drawable, states) unless drawable.is_a?(Animation) && drawable.hidden?
      end
    end
  end
end

class Player < Entity
  include Drawable
  include Properties(Health, Rotation, Position, Velocity, Acceleration, Inventory, EquippedItems, Drawables)
  include Behaviors(FaceMouse)
end

class SpriteSheet
  property id : Int32
  property dir : String

  def initialize(@id : Int32, @dir : String)
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

  def entries
    raise "Directory does not exist: #{dir}" unless Dir.exists?(dir)
    @entries ||= Dir.new(dir).entries.reject { |e| [".", ".."].includes?(e) }.as(Array(String))
  end

  def num_textures
    @num_textures ||= entries.size.as(Int32)
  end

  def texture_prefix
    @texture_prefix ||= File.basename(entries.first).split('_')[0...-1].join('_').as(String)
  end

  def texture_extension
    @texture_extension ||= File.extname(entries.first).as(String)
  end

  def texture_path(id)
    "#{texture_prefix}_#{id}#{texture_extension}"
  end

  def files
    @files ||= (0...num_textures).map { |i| File.join(dir, texture_path(i)) }.as(Array(String))
  end

  def render_texture
    SF::RenderTexture.new(sheet_size.x, sheet_size.y, false).tap do |sheet|
      sheet.clear
      files.each_with_index { |file, i| sheet.draw(sprite(file, texture_size.x * i)) }
      sheet.display
    end
  end

  def texture
    @texture ||= render_texture.texture.as(SF::Texture)
  end
end

class Animation
  include SF::Drawable

  @@selected_debug_anim = 1

  property id : Int32 = 0
  property name : String = "Unnamed"
  property entity : Entity = Entity.new
  property sprite_sheet : SpriteSheet
  property duration : Float32 = 0.0f32
  property origin : (SF::Vector2f | Tuple(Float32, Float32)) = SF.vector2f(0.0, 0.0)
  property? loop : Bool = false
  property? interruptable : Bool = false
  property t : Float32 = 0.0f32
  property curr_frame : Int32 = 0
  property? paused : Bool = false
  property? visible : Bool = false

  def initialize(@id, @name, @entity, @sprite_sheet, @duration, @origin : SF::Vector2f | Tuple(Float32, Float32), @loop)
  end

  def sprite
    @sprite ||= SF::Sprite.new(texture, texture_rect).tap { |s|
      s.position = entity.position
      s.rotation = entity.rotation
      s.origin = origin
    }.as(SF::Sprite)
  end

  def num_frames
    @num_frames ||= (sprite_sheet.num_textures).as(Int32)
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
    !paused? && t >= frame_length
  end

  def finished?
    curr_frame >= (num_frames - 1)
  end

  def show
    @visible = true
  end

  def hide
    @visible = false
  end

  def hidden?
    !visible?
  end

  def pause
    @paused = true
  end

  def restart
    @t = 0.0f32
    @curr_frame = 0
    sprite.texture_rect = texture_rect
  end

  def update(dt)
    @t += dt
    return unless next_frame?
    @t = 0.0f32
    if finished?
      if entity.is_a?(Drawable) && !loop?
        self.hide
        entity.as(Drawable).tap do |e|
          e.drawables[:current_sprite] = e.drawables[:default_sprite]
          e.drawables[:current_sprite].as(Animation).tap do |a|
            a.show
            a.curr_frame = 0
            a.sprite.rotation = sprite.rotation
            a.sprite.position = sprite.position
            a.update(dt)
          end
        end
      end
      @curr_frame = 0
    else
      @curr_frame = curr_frame + 1
    end
    sprite.tap { |s|
      s.texture_rect = texture_rect
      s.position = entity.position
      s.rotation = entity.rotation
      s.origin = origin
    }
  end

  def draw(target : SF::RenderTarget, states : SF::RenderStates)
    target.draw(sprite, states)
  end

  def self.selected_debug_anim
    @@selected_debug_anim
  end

  def self.selected_debug_anim=(num)
    @@selected_debug_anim = num
  end
end

class Game
  property t : Float32 = 0.0f32
  property accumulator : Float32 = 0.0f32
  property? show_debug_menu : Bool = false
  property idle_animation
  property melee_animation
  property move_animation
  property reload_animation
  property shoot_animation
  property anim_frame : Int32 = 1
  property entity_count : Int32 = 0

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
    @cursor ||= SF::Cursor.from_system(SF::Cursor::Cross)
  end

  def render_states
    @render_states ||= SF::RenderStates.new
  end

  def screen
    @screen ||= render_states
      .transform
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
        rotation:     90.0f32,
        position:     {500.0, 500.0},
        velocity:     {0.0f32, 0.0f32},
        acceleration: {0.0f32, 0.0f32},
        drawables:    {
          :body => SF::CircleShape.new.tap { |c|
            c.position = {500.0, 500.0}
            c.radius = 25.0
            c.origin = {25.0, 25.0}
            c.fill_color = SF::Color::Black
            c.outline_color = SF::Color::Green
            c.outline_thickness = scale * 1.25
          },
        } of Symbol => SF::Drawable,
      }
    ).tap { |p|
      @player = p
      p.drawables[:default_sprite] = idle_animation
      p.drawables[:current_sprite] = idle_animation.tap(&.show)
    }.as(Player)
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
        when SF::Keyboard::R
          player.drawables[:current_sprite].as(Animation).hide if player.drawables[:current_sprite].is_a?(Animation)
          player.drawables[:current_sprite] = reload_animation.tap { |a| a.restart; a.show }
        when SF::Keyboard::F
          player.drawables[:current_sprite].as(Animation).hide if player.drawables[:current_sprite].is_a?(Animation)
          player.drawables[:current_sprite] = melee_animation.tap { |a| a.restart; a.show }
        when SF::Keyboard::W,
             SF::Keyboard::A,
             SF::Keyboard::S,
             SF::Keyboard::D
          player.drawables[:current_sprite].as(Animation).hide if player.drawables[:current_sprite].is_a?(Animation)
          player.drawables[:current_sprite] = move_animation.tap { |a| a.show }
        end
      when SF::Event::MouseButtonPressed
        player.drawables[:current_sprite].as(Animation).hide if player.drawables[:current_sprite].is_a?(Animation)
        player.drawables[:current_sprite] = shoot_animation.tap { |a| a.show }
        # Shotgun.new.primary_attack
        # spawn_ball if event.button == SF::Mouse::Left && !show_debug_menu?
      end
    end
  end

  def animations
    @animations ||= AnimationData
      .init(player, sprite_sheets)
      .from_json(File.read("data/animations/player.json"))
      .animations
      .tap { |a| puts "loading animations..." }
      .as(Hash(String, Animation))
  end

  def sprite_sheets
    @sprite_sheets ||= SpriteSheetData
      .from_json(File.read("data/sprite_sheets/player.json"))
      .sprite_sheets
      .tap { |s| puts "loading sprite_sheets..." }
      .as(Hash(Int32, SpriteSheet))
  end

  def idle_animation
    @idle_animation ||= animations["player_shotgun_idle"].as(Animation)
  end

  def melee_animation
    @melee_animation ||= animations["player_shotgun_melee"].as(Animation)
  end

  def move_animation
    @move_animation ||= animations["player_shotgun_move"].as(Animation)
  end

  def reload_animation
    @reload_animation ||= animations["player_shotgun_reload"].as(Animation)
  end

  def shoot_animation
    @shoot_animation ||= animations["player_shotgun_shoot"].as(Animation)
  end

  def debug_menu
    imgui.set_next_window_size(ImVec2.new(430, 450), LibImGui::ImGuiCond::FirstUseEver)
    if !imgui.begin("Property editor")
      imgui.end
      return
    end
    imgui.push_style_var(LibImGui::ImGuiStyleVar::FramePadding, ImVec2.new(2, 2))
    imgui.align_text_to_frame_padding
    player.property_tree
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
        player.drawables[:current_sprite].tap { |a| a.update(dt) if a.is_a?(Animation) }

        @accumulator -= dt
        @t += dt
      end

      window.clear
      window.draw(player)

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
