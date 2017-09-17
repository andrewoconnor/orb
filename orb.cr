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

    def initialize(**attributes)
      super **attributes
    end

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

    def initialize(opts)
      super **attributes
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

class Foo < Entity
  include Health
  include Position
end

f = Foo.new(**{hp: 80, max_hp: 100, x: 0, y: 0})
p f


# game = Game.new
# game.run
# 