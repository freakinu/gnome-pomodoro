/*
 * Copyright (c) 2016 gnome-pomodoro contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 *
 */


namespace Pomodoro
{
    [GtkTemplate (ui = "/org/gnome/pomodoro/window.ui")]
    public class Window : Gtk.ApplicationWindow, Gtk.Buildable
    {
        private const int MIN_WIDTH = 500;
        private const int MIN_HEIGHT = 650;

        private const double FADED_IN = 1.0;
        private const double FADED_OUT = 0.2;

        private const double TIMER_LINE_WIDTH = 6.0;
        private const double TIMER_RADIUS = 165.0;

        private struct Name
        {
            public string name;
            public string display_name;
        }

        private const Name[] STATE_NAMES = {
            { "null", "" },
            { "pomodoro", N_("Pomodoro") },
            { "short-break", N_("Short Break") },
            { "long-break", N_("Long Break") }
        };

        public string mode {
            get {
                return this.stack.visible_child_name;
            }
            set {
                this.stack.visible_child_name = value;
            }
        }

        public string default_mode {
            get {
                return this.default_page;
            }
        }

        private unowned Pomodoro.Timer timer;

        [GtkChild]
        private unowned Gtk.Stack stack;
        [GtkChild]
        private unowned Gtk.Stack timer_stack;
        [GtkChild]
        private unowned Gtk.ToggleButton state_togglebutton;
        [GtkChild]
        private unowned Gtk.Label formated_label;
        [GtkChild]
        private unowned Gtk.Widget timer_box;
        [GtkChild]
        private unowned Gtk.Button pause_button;
        [GtkChild]
        private unowned Gtk.Image pause_button_image;

        private Pomodoro.Animation blink_animation;
        private string default_page;

        construct
        {
            var geometry = Gdk.Geometry () {
                min_width = MIN_WIDTH,
                max_width = -1,
                min_height = MIN_HEIGHT,
                max_height = -1
            };
            this.set_geometry_hints (this, geometry, Gdk.WindowHints.MIN_SIZE);

            // this.stack.add_titled (this.timer_stack, "timer", _("Timer"));
            this.stack.add_titled (new Pomodoro.StatsView (), "stats", _("Stats"));

            // TODO: this.default_page should be set from application.vala
            var application = Pomodoro.Application.get_default ();

            // if (application.capabilities.has_enabled ("task-list")) {  // TODO
            //     this.default_page = "task-list";
            // }
            if (application.capabilities.has_capability ("indicator")) {
                this.default_page = "stats";
            }
            else {
                this.default_page = "timer";
            }

            this.stack.visible_child_name = this.default_page;

            this.on_timer_state_notify ();
            this.on_timer_elapsed_notify ();
            this.on_timer_is_paused_notify ();
        }

        public void parser_finished (Gtk.Builder builder)
        {
            this.timer = Pomodoro.Timer.get_default ();
            this.insert_action_group ("timer", this.timer.get_action_group ());

            base.parser_finished (builder);

            var state_togglebutton = builder.get_object ("state_togglebutton");
            state_togglebutton.bind_property ("active",
                                              builder.get_object ("state_popover"),
                                              "visible",
                                              GLib.BindingFlags.BIDIRECTIONAL);

            this.timer.notify["state"].connect_after (this.on_timer_state_notify);
            this.timer.notify["elapsed"].connect_after (this.on_timer_elapsed_notify);
            this.timer.notify["is-paused"].connect_after (this.on_timer_is_paused_notify);
        }

        private void on_blink_animation_complete ()
        {
            if (this.timer.is_paused) {
                this.blink_animation.start_with_value (1.0);
            }
        }

        private void on_timer_state_notify ()
        {
            this.timer_stack.visible_child_name = 
                    (this.timer.state is Pomodoro.DisabledState) ? "disabled" : "enabled";

            foreach (var mapping in STATE_NAMES)
            {
                if (mapping.name == this.timer.state.name && mapping.display_name != "") {
                    this.state_togglebutton.label = mapping.display_name;
                    break;
                }
            }
        }

        private void on_timer_elapsed_notify ()
        {
            if (!(this.timer.state is Pomodoro.DisabledState))
            {
                var remaining = (uint) double.max (Math.ceil (this.timer.remaining), 0.0);
                this.formated_label.label = format_time2((int) remaining);
                
                this.timer_box.queue_draw ();
            }
        }

        private void on_timer_is_paused_notify ()
        {
            if (this.blink_animation != null) {
                this.blink_animation.stop ();
                this.blink_animation = null;
            }

            if (this.timer.is_paused) {
                this.pause_button_image.icon_name = "media-playback-start-symbolic";
                this.pause_button.action_name     = "timer.resume";
                this.pause_button.tooltip_text    = _("Resume");

                this.blink_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.BLINK,
                                                               2500,
                                                               25);
                this.blink_animation.add_property (this.timer_box,
                                                   "opacity",
                                                   FADED_OUT);
                this.blink_animation.complete.connect (this.on_blink_animation_complete);
                this.blink_animation.start_with_value (1.0);
            }
            else {
                this.pause_button_image.icon_name = "media-playback-pause-symbolic";
                this.pause_button.action_name     = "timer.pause";
                this.pause_button.tooltip_text    = _("Pause");

                this.blink_animation = new Pomodoro.Animation (Pomodoro.AnimationMode.EASE_OUT,
                                                               200,
                                                               50);
                this.blink_animation.add_property (this.timer_box,
                                                   "opacity",
                                                   1.0);
                this.blink_animation.start ();
            }
        }

        [GtkCallback]
        private bool on_timer_box_draw (Gtk.Widget    widget,
                                        Cairo.Context context)
        {
            if (!(this.timer.state is Pomodoro.DisabledState))
            {
                var style_context = widget.get_style_context ();
                var color         = style_context.get_color (widget.get_state_flags ());

                var width  = widget.get_allocated_width ();
                var height = widget.get_allocated_height ();
                var x      = 0.5 * width;
                var y      = 0.5 * height;
                var progress = this.timer.state_duration > 0.0
                        ? this.timer.elapsed / this.timer.state_duration : 0.0;

                var angle1 = - 0.5 * Math.PI - 2.0 * Math.PI * progress.clamp (0.000001, 1.0);
                var angle2 = - 0.5 * Math.PI;

                context.set_line_width (TIMER_LINE_WIDTH);

                context.set_source_rgba (color.red,
                                         color.green,
                                         color.blue,
                                         color.alpha * 0.1);
                context.arc (x, y, TIMER_RADIUS, 0.0, 2 * Math.PI);
                context.stroke ();

                context.set_line_cap (Cairo.LineCap.ROUND);
                context.set_source_rgba (color.red,
                                         color.green,
                                         color.blue,
                                         color.alpha * FADED_IN - (color.alpha * 0.1) * (1.0 - FADED_IN));

                context.arc_negative (x, y, TIMER_RADIUS, angle1, angle2);
                context.stroke ();
            }

            return false;
        }

        [GtkCallback]
        private bool on_button_press (Gtk.Widget      widget,
                                      Gdk.EventButton event)
        {
            if (event.button == 1) {
                this.begin_move_drag ((int) event.button, (int) event.x_root, (int) event.y_root, event.time);

                return true;
            }

            return false;
        }
    }
}
