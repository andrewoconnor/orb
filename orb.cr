require "crsfml"

class Game
  def mode
    @mode ||= SF::VideoMode.new(1920, 1080)
  end

  def window
    @window ||= SF::RenderWindow.new(mode, "orb")
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
    property x : Int32?,
             y : Int32?

    def x
      @x ||= 0
    end

    def y
      @y ||= 0
    end
  end
end

module Name
  macro included
    property name : String?

    def name
      @name ||= ""
    end
  end
end

class Entity
  def initialize(**attributes)
    {% for var in @type.instance_vars %}
      if arg = attributes[:{{var.name.id}}]?
        @{{var.name.id}} = arg
      end
    {% end %}
  end
end

class Player < Entity
  include Name
  include Health
  include Position
end

p1 = Player.new(**{hp: 80, full_hp: 100, max_hp: 100})
p p1
p1.x = 100
p p1.name

# game = Game.new
# game.run
# 