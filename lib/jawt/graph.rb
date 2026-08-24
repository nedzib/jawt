# frozen_string_literal: true

module Jawt
  class Graph
    BOX_HEIGHT = 3
    V_GAP = 3
    H_GAP = 2
    PADDING = 1

    def initialize(workflow)
      @workflow = workflow
    end

    def render
      order = topo_order
      depth = compute_depth(order)
      width = box_width
      level_columns = group_columns(order, depth)

      canvas = Canvas.new(width: total_width(width, level_columns),
                          height: total_height(depth, level_columns))

      positions = {}
      level_columns.each do |level, ids|
        level_width = ids.size * width + (ids.size - 1) * H_GAP
        offset = (canvas.width - level_width) / 2
        ids.each_with_index do |id, i|
          positions[id] = {
            left: offset + i * (width + H_GAP),
            top: level * (BOX_HEIGHT + V_GAP)
          }
        end
      end

      draw_edges(canvas, positions)
      draw_boxes(canvas, positions)
      canvas.to_s
    end

    def box_width
      max = @workflow.nodes.keys.map { |id| @workflow.label(id).length }.max || 0
      max + (PADDING * 2) + 2
    end

    private

    def topo_order
      indegree = @workflow.nodes.keys.to_h { |id| [id, 0] }
      adjacency = @workflow.nodes.keys.to_h { |id| [id, []] }
      @workflow.edges.each do |edge|
        next unless @workflow.node(edge.from.node) && @workflow.node(edge.to.node)

        adjacency[edge.from.node] << edge.to.node
        indegree[edge.to.node] += 1
      end

      queue = indegree.select { |_, d| d.zero? }.keys.sort
      order = []
      until queue.empty?
        n = queue.shift
        order << n
        adjacency[n].sort.each do |m|
          indegree[m] -= 1
          queue << m if indegree[m].zero?
        end
      end
      order.concat(@workflow.nodes.keys.sort - order)
      order
    end

    def compute_depth(order)
      depth = Hash.new(0)
      order.each do |id|
        preds = @workflow.incoming_edges(id).map { |e| e.from.node }.select { |p| depth.key?(p) }
        depth[id] = preds.map { |p| depth[p] + 1 }.max || 0
      end
      depth
    end

    def group_columns(order, depth)
      order.group_by { |id| depth[id] }.sort.to_h
    end

    def total_width(width, level_columns)
      level_columns.values.map { |ids| ids.size * width + (ids.size - 1) * H_GAP }.max || width
    end

    def total_height(_depth, level_columns)
      levels = level_columns.size
      levels * BOX_HEIGHT + (levels - 1) * V_GAP
    end

    def center(positions, id)
      pos = positions[id]
      pos[:left] + box_width / 2
    end

    def draw_edges(canvas, positions)
      outgoing_index = Hash.new(0)
      @workflow.edges.each do |edge|
        next unless positions.key?(edge.from.node) && positions.key?(edge.to.node)

        x1 = center(positions, edge.from.node)
        x2 = center(positions, edge.to.node)
        y1 = positions[edge.from.node][:top] + BOX_HEIGHT
        y2 = positions[edge.to.node][:top]

        route = y1 + outgoing_index[edge.from.node]
        outgoing_index[edge.from.node] += 1

        canvas.vline(x1, y1, route)
        canvas.hline(x1, x2, route)
        canvas.vline(x2, route, y2 - 1)
        canvas.mark_arrow(x2, y2 - 1)
      end
    end

    def draw_boxes(canvas, positions)
      positions.each do |id, pos|
        canvas.box(pos[:left], pos[:top], box_width, BOX_HEIGHT, @workflow.label(id))
      end
    end

    class Canvas
      attr_reader :width, :height

      def initialize(width:, height:)
        @width = width
        @height = height
        @grid = Array.new(height) { Array.new(width, " ") }
        @pipe = Hash.new(false)
        @arrows = Hash.new(false)
      end

      def vline(x, y1, y2)
        ([y1, y2].min..[y1, y2].max).each do |y|
          @pipe[[x, y]] = true if in_bounds?(x, y)
        end
      end

      def hline(x1, x2, y)
        ([x1, x2].min..[x1, x2].max).each do |x|
          @pipe[[x, y]] = true if in_bounds?(x, y)
        end
      end

      def mark_arrow(x, y)
        return unless in_bounds?(x, y)

        @arrows[[x, y]] = true
        @pipe[[x, y]] = true
      end

      def box(left, top, width, height, label)
        return unless in_bounds?(left, top) && in_bounds?(left + width - 1, top + height - 1)

        (0...width).each do |dx|
          @grid[top][left + dx] = "─"
          @grid[top + height - 1][left + dx] = "─"
        end
        @grid[top][left] = "┌"
        @grid[top][left + width - 1] = "┐"
        @grid[top + height - 1][left] = "└"
        @grid[top + height - 1][left + width - 1] = "┘"

        (1...height - 1).each do |dy|
          @grid[top + dy][left] = "│"
          @grid[top + dy][left + width - 1] = "│"
        end

        content_row = top + height / 2
        start = left + 1 + PADDING
        label.chars.each_with_index do |ch, i|
          @grid[content_row][start + i] = ch if in_bounds?(start + i, content_row)
        end
      end

      def to_s
        @grid.map.with_index do |row, y|
          row.map.with_index do |cell, x|
            if @arrows[[x, y]]
              "▼"
            elsif @pipe[[x, y]]
              junction(x, y)
            else
              cell
            end
          end.join.rstrip
        end.join("\n")
      end

      private

      def junction(x, y)
        u = @pipe[[x, y - 1]]
        d = @pipe[[x, y + 1]]
        l = @pipe[[x - 1, y]]
        r = @pipe[[x + 1, y]]
        return "┼" if u && d && l && r
        return "┤" if u && d && l
        return "├" if u && d && r
        return "┴" if u && l && r
        return "┬" if d && l && r
        return "│" if u && d
        return "─" if l && r
        return "└" if u && r
        return "┘" if u && l
        return "┌" if d && r
        return "┐" if d && l
        return "│" if u || d
        return "─" if l || r

        "┼"
      end

      def in_bounds?(x, y)
        x >= 0 && x < width && y >= 0 && y < height
      end
    end
  end
end
