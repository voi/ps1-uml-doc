# ps1
## constant various
Set-Variable -Name X_START  -Value 200 -Option Constant
Set-Variable -Name Y_START  -Value 25  -Option Constant
Set-Variable -Name X_OFFSET -Value 200 -Option Constant
Set-Variable -Name Y_OFFSET -Value 50  -Option Constant
Set-Variable -Name PARTICIPANT_WIDTH -Value 150 -Option Constant
Set-Variable -Name PARTICIPANT_HEIGHT -Value 25 -Option Constant
Set-Variable -Name ARROW_WIDTH -Value 10 -Option Constant
Set-Variable -Name ARROW_HEIGHT -Value 10 -Option Constant
Set-Variable -Name TERM_R -Value 10 -Option Constant
Set-Variable -Name TERM_Y_OFFSET -Value 20 -Option Constant
Set-Variable -Name ACTIVATE_WIDTH -Value 11 -Option Constant
Set-Variable -Name SVG_CSS -Value @"

.participant {
     stroke: #000000;
     stroke-width: 1px;
     fill: #FFFFFF;
}

.note {
}

.active {
     stroke: #000000;
     stroke-width: 1px;
     fill: lightgrey;
}

text {
     font-family: arial;
     font-size: 16;
     fill: #000000;
}

.name {
     text-anchor: middle;
}

line {
     stroke: #000000;
     stroke-width: 1px;
}

path {
     stroke: #000000;
     stroke-width: 2px;
}

.lifeline {
     stroke-dasharray: 5,5;
}

.message {
     fill: none;
}

.term {
     fill: #000000;
}

.head {
     fill: #000000;
}

.return {
     stroke-dasharray: 10,5;
}

.fragment {
     fill: none;
}

.else {
     stroke-dasharray: 10,5;
}

"@ -Option Constant
Set-Variable -Name ARROW_MAP -Value @{
  '-->' = 'CALL'; '<--' = 'CALL';
  '->>' = 'POST'; '<<-' = 'POST';
  'START' = 'CALL';
  'SIGNAL' = 'POST'; 'TIMER' = 'POST';
} -Option Constant


function Trim_Token($original) {
  if ($null -eq $original) {
    ''
  }
  else {
    $original -replace '^\s+', '' -replace '\s+$', ''
  }
}

function Create_Participant($name) {
  @{
    Type        = 'PARTICIPANT';
    Name        = $name;
    ActiveLevel = 0;
    Note        = '';
  }
}

function Create_Activate($command, $x, $y) {
  @{
    Command = $command;
    X       = $x;
    Y       = $y;
  }
}

function Create_Fragment($command, $y) {
  @{
    Command = $command;
    MinX    = [System.UInt32]::MaxValue;
    MaxX    = [System.UInt32]::MinValue;
    Elses   = @();
    Y       = $y;
  }
}

##
foreach ( $arg in $args | Where-Object { Test-Path $_ } ) {
  #### lexer & parser?
  $commands = @()
  $aliases = @{ }
  $participants = @{ }
  $line_no = 1

  foreach ($line in Get-Content -Path $arg -Encoding UTF8) {
    switch -regex (($line -replace '^\s+', '' -replace '\s+$', '')) {
      # participant, alias
      '^participant\s+(\S+)(?:\s+:\s+(\S.*))?$' {
        #
        $name = Trim_Token $matches[2]
        $alias = Trim_Token $matches[1]

        $is_duplicated = if ($null -eq $name) {
          $aliases.ContainsKey($alias)
        }
        else {
          $aliases.ContainsKey($name)
        }

        # check defintion duplicated.
        if ($nul -eq $name) {
          $name = $alias
        }

        if ($is_duplicated) {
          #
          Write-Debug "$line_no : duplicate participant alias."
          Write-Debug "    $line"
        }
        else {
          # 
          $commands += Create_Participant $name

          $aliases[$alias] = $name
          $participants[$name] = @{
            Order         = $participants.Count;
            ActivateLevel = 0;
          }
        }
      }

      # method call, message, return
      '^(\S+)\s+(-->|<--|->>|<<-)\s+(\S+)(\s+,,)?(?:\s*:\s+(\S.*))?$' {
        #
        $tokens = $matches[1..5] | Foreach-Object { Trim_Token $_ }

        $command = @{
          Type        = 'SEQ';
          Caller      = $tokens[0];
          Callee      = $tokens[2];
          Arrow       = $ARROW_MAP[$tokens[1]];
          Description = $tokens[4];
          Note        = '';
        }

        if ($tokens[1] -match '<--|<<-') {
          $command.Caller = Trim_Token $tokens[2]
          $command.Callee = Trim_Token $tokens[0]
        }

        if ($command.Callee -eq '&') {
          $command.Callee = $command.Caller
        }

        #
        $caller = $command.Caller

        if ($aliases.ContainsKey($caller)) {
          # resolve alias
          $command.Caller = $aliases[$caller]
        }
        else {
          # check new participant
          if (-not $aliases.ContainsValue($caller)) {
            $commands += Create_Participant $caller

            $aliases[$caller] = $caller
            $participants[$caller] = @{
              Order         = $participants.Count;
              ActivateLevel = 0;
            }
          }
        }

        # check new callee participant
        $callee = $command.Callee

        if ($aliases.ContainsKey($callee)) {
          # resolve alias
          $command.Callee = $aliases[$callee]
        }
        else {
          # check new participant
          if (-not $aliases.ContainsValue($callee)) {
            $commands += Create_Participant $callee

            $aliases[$callee] = $callee
            $participants[$callee] = @{
              Order         = $participants.Count;
              ActivateLevel = 0;
            }
          }
        }
        #
        $commands += $command

        #
        if ($tokens[3] -eq ',,') {
          $commands += @{
            Type        = 'RETURN';
            Description = '';
            Note        = '';
          }
        }
      }

      # return/exit
      '^(return|exit)(?:\s*:\s+(\S.*))?$' {
        $tokens = $matches[1..2]
        $commands += @{
          Type        = $tokens[0].ToUpper();
          Description = Trim_Token $tokens[1];
          Note        = '';
        }
      }

      # start/signal/timer
      '^(start|signal|timer)\s+(\S+)(?:\s*:\s+(\S.*))?$' {
        $tokens = $matches[1..3]
        $command = @{
          Type        = $tokens[0].ToUpper();
          Callee      = Trim_Token $tokens[1];
          Arrow       = $ARROW_MAP[$tokens[0].ToUpper()];
          Description = Trim_Token $tokens[2];
          Note        = ''
        }
        $callee = $command.Callee

        if ($aliases.ContainsKey($callee)) {
          # resolve alias
          $command.Callee = $aliases[$callee]
        }
        else {
          # check new participant
          if (-not $aliases.ContainsValue($callee)) {
            $commands += Create_Participant $callee

            $aliases[$callee] = $callee
            $participants[$callee] = @{
              Order         = $participants.Count;
              ActivateLevel = 0;
            }
          }
        }

        $commands += $command
      }

      # note
      '^Note(?:\s*:\s+(\S.*))?$' {
        if ($commands.Count -gt 0) {
          $commands[-1].Note += Trim_Token $matches[1];
        }
      }

      # ref frafment
      '^ref(?:\s+((?:\S+\s+)+))?(\s*:\s+\S.*)?$' {
        $part = Trim_Token $matches[1]
        $desc = Trim_Token $matches[2]

        if ($part -match ':\s+') {
          $desc = $part
          $part = ''
        }

        $commands += @{
          Type         = 'REF';
          Description  = $desc -replace ':\s+', '';
          Participants = @($part -split '\s+')
          Note         = '';
        }
      }

      # loop/opt/alt/par/break/cirtical fragment
      '^(loop|opt|alt|par|break|critical|assert|neg|ignore|consider)(?:\s+:\s+(\S.*))?$' {
        $commands += @{
          Type        = 'FRAGMENT';
          Name        = Trim_Token $matches[1]
          Description = Trim_Token $matches[2];
          Includes    = @()
          X           = 0;
          Note        = '';
        }
      }

      # else (alt/par)
      '^else(?:\s*:\s+(\S.*))?$' {
        $commands += @{
          Type        = 'ELSE';
          Description = Trim_Token $matches[1]
          Includes    = @()
          X           = 0;
          Note        = '';
        }
      }

      # end of fragment
      '^end$' {
        $commands += @{
          Type = 'END';
          Note = '';
        }
      }

      # comment
      '^//\s*(\S.*)$' {
        # NOP
      }

      # empty line
      '^\s*$' {
        # NOP
      }

      # other
      default {
        #
        Write-Debug "$line_no : unexpected command line."
        Write-Debug "    $line"
      }
    }

    $line_no += 1
  }

  ##
  $seq_count = 1 + ($commands | Where-Object { $_.Type -ne 'PARTICIPANT' }).Count
  $SVG_WIDTH = ($X_START + $X_OFFSET * ($commands | Where-Object { $_.Type -eq 'PARTICIPANT' }).Count)
  $SVG_HEIGHT = ($Y_START + $Y_OFFSET * ($seq_count * 1.2))
    
  ##
  $doc = New-Object System.Xml.XmlDocument

  $html = $doc.AppendChild($doc.CreateElement('html'))

  #
  $head = $html.AppendChild($doc.CreateElement('head'))

  $meta = $head.AppendChild($doc.CreateElement('meta'))
  $meta.SetAttribute('charset', 'UTF-8')

  $style = $head.AppendChild($doc.CreateElement('style'))
  $style.SetAttribute('type', 'text/css')
  $style.InnerText = $SVG_CSS
  # $style.AppendChild($doc.CreateCDataSection($SVG_CSS)) | Out-Null

  #
  $body = $html.AppendChild($doc.CreateElement('body'))

  $svg = $body.AppendChild($doc.CreateElement('svg'))
  $svg.SetAttribute('version', '1.1')
  $svg.SetAttribute('xmlns', 'http://wwww.w3c.org/2000/svg')
  $svg.SetAttribute('xmlns:xlink', 'http://www.w3c.org/1999/xlink')
  $svg.SetAttribute('viewBox', "0 0 $SVG_WIDTH $SVG_HEIGHT")
  $svg.SetAttribute('width', "$SVG_WIDTH")
  $svg.SetAttribute('height', "$SVG_HEIGHT")

  #
  $base_g = $svg.AppendChild($doc.CreateElement('g'))
  $act_g = $svg.AppendChild($doc.CreateElement('g'))
  $seq_g = $svg.AppendChild($doc.CreateElement('g'))
  $frag_g = $svg.AppendChild($doc.CreateElement('g'))

  ##
  $activate_stack = @()
  $frame_stack = @()
  $y_count = 1

  foreach ($command in $commands) {
    switch ($command.Type) {
      #
      'PARTICIPANT' {
        $x_base = $X_START + $X_OFFSET * $participants[$command.Name].Order

        # lifeline
        $node = $base_g.AppendChild($doc.CreateElement('path'))
        $node.SetAttribute('class', 'lifeline')
        $node.SetAttribute('d', ('M {0} {1} V {2}' -f $x_base, $Y_START, ($Y_START + (($Y_OFFSET + 1) * $seq_count * 1.2))))

        # participant figure
        $x = $x_base - ($PARTICIPANT_WIDTH / 2)
        $y = $Y_START - ($PARTICIPANT_HEIGHT / 2)

        $node = $base_g.AppendChild($doc.CreateElement('rect'))
        $node.SetAttribute('class', 'participant')
        $node.SetAttribute('x', $x.ToString())
        $node.SetAttribute('y', $y.ToString())
        $node.SetAttribute('width', $PARTICIPANT_WIDTH.ToString())
        $node.SetAttribute('height', $PARTICIPANT_HEIGHT.ToString())

        # participant name
        $x = $x_base
        $y = $Y_START + ($PARTICIPANT_HEIGHT / 2)

        $node = $base_g.AppendChild($doc.CreateElement('text'))
        $node.SetAttribute('class', 'name')
        $node.SetAttribute('x', $x + 5)
        $node.SetAttribute('y', $y - 5)
        $node.AppendChild($doc.CreateTextNode($command.Name)) | Out-Null
      }
      #
      { $_ -match 'SEQ|START|SIGNAL|TIMER' } {
        # common location
        $participants[$command.Callee].ActivateLevel += 1

        $x_to = $X_START + $X_OFFSET * $participants[$command.Callee].Order
        $x_from = if ($null -ne $command.Caller) {
          $X_START + $X_OFFSET * $participants[$command.Caller].Order
        }
        else {
          $x_to - 100
        }
        $y = $Y_START + $Y_OFFSET * $y_count

        # activate level
        $activate_stack += Create_Activate $command $x_to $y

        # include fragment
        $fragment = $frame_stack[-1]

        if ($null -ne $fragment) {
          $fragment.MinX = [System.Math]::Min($fragment.MinX, [System.Math]::Min($x_from, $x_to))
          $fragment.MaxX = [System.Math]::Max($fragment.MaxX, [System.Math]::Max($x_from, $x_to))
        }

        # arrow line
        $node = $seq_g.AppendChild($doc.CreateElement('path'))

        $node.SetAttribute('class', 'message')

        if ($x_from -ne $x_to) {
          if (($command.Type -eq 'SIGNAL') -or ($command.Type -eq 'TIMER')) {
            $node.SetAttribute('d', @(
                ('M {0} {1}' -f $x_from, ($y - $TERM_Y_OFFSET)),
                ('h {0}' -f [System.Math]::Floor(($x_to - $x_from) * 0.7)),
                ('l {0} {1}' -f [System.Math]::Floor(($x_to - $x_from) * -0.4), $TERM_Y_OFFSET),
                ('h {0}' -f [System.Math]::Floor(($x_to - $x_from) * 0.7))
              ) -join ' ')
          }
          else {
            $node.SetAttribute('d', ('M {0} {1} H {2}' -f $x_from, $y, $x_to))
          }
        }
        else {
          $node.SetAttribute('d', ('M {0} {1} h 50 v 20 h -50' -f $x_from, $y))
        }

        # arrow head
        $node = $seq_g.AppendChild($doc.CreateElement('path'))

        $node.SetAttribute('class', 'head')

        $y_head = if ($x_from -ne $x_to) { $y } else { $y + 20 }

        if ($command.Arrow -eq 'CALL') {
          # -|>
          $node.SetAttribute('d', @(
              ('M {0} {1}' -f $x_to, $y_head),
              ('l {0} {1}' -f (-1 * $ARROW_WIDTH), (-1 * $ARROW_HEIGHT / 2)),
              ('v {0}' -f $ARROW_HEIGHT),
              'z'
            ) -join ' ')
        }
        else {
          # -->
          $node.SetAttribute('d', @(
              ('M {0} {1}' -f ($x_to - $ARROW_WIDTH), ($y_head - $ARROW_HEIGHT / 2)),
              ('l {0} {1}' -f $ARROW_WIDTH, ($ARROW_HEIGHT / 2)),
              ('l {0} {1}' -f (-1 * $ARROW_WIDTH), ($ARROW_HEIGHT / 2)),
              ('L {0} {1}' -f $x_to, $y_head)
            ) -join ' ')
        }

        if ($x_from -ge $x_to) {
          $node.SetAttribute('transform', ('rotate(180 {0} {1})' -f $x_to, $y_head))
        }

        # arrow description
        $node = $seq_g.AppendChild($doc.CreateElement('text'))
        $node.AppendChild($doc.CreateTextNode($command.Description)) | Out-Null

        $x = if ($x_from -gt $x_to) { $x_to } else { $x_from }

        $node.SetAttribute('x', ($x + 10).ToString())
        $node.SetAttribute('y', ($y - 5).ToString())

        #
        switch ($command.Type) {
          'START' {
            $node = $seq_g.AppendChild($doc.CreateElement('circle'))

            $node.SetAttribute('class', 'term')
            $node.SetAttribute('cx', ($x_from - $TERM_R).ToString())
            $node.SetAttribute('cy', $y.ToString())
            $node.SetAttribute('r', $TERM_R)
          }
          'SIGNAL' {
            $node = $seq_g.AppendChild($doc.CreateElement('circle'))

            $node.SetAttribute('class', 'term')
            $node.SetAttribute('cx', ($x_from - $TERM_R).ToString())
            $node.SetAttribute('cy', ($y - $TERM_Y_OFFSET).ToString())
            $node.SetAttribute('r', $TERM_R)
          }
          'TIMER' {
            $node = $seq_g.AppendChild($doc.CreateElement('path'))

            $node.SetAttribute('d', @(
                ('M {0} {1}' -f $x_from, ($y - $TERM_Y_OFFSET)),
                ('m -10 -10'),
                ('h 20')
                ('l -20 20'),
                ('h 20'),
                ('l -20 -20')
              ) -join ' ')
          }
        }

        #
        $y_count += 1
      }
      #
      { $_ -match 'RETURN|EXIT' } {
        #
        $begin = $activate_stack[-1]

        if ($null -ne $begin) {
          # pop stack
          $activate_stack = $activate_stack[0..($activate_stack.Length - 2)] 

          # common location
          $x_from = $X_START + $X_OFFSET * $participants[$begin.Command.Callee].Order
          $x_to = if ($command.Type -eq 'EXIT') {
            $x_from - 100
          }
          else {
            $X_START + $X_OFFSET * $participants[$begin.Command.Caller].Order
          }
          $is_self = ($x_from -eq $x_to)

          $y = if ($is_self) {
            $Y_START + $Y_OFFSET * ($y_count - 1) + 20
          }
          else {
            $Y_START + $Y_OFFSET * $y_count
          }

          # activate line
          $actLv = $participants[$begin.Command.Callee].ActivateLevel - 1
          $participants[$begin.Command.Callee].ActivateLevel -= 1

          $act = if ($act_g.HasChildNodes) {
            $act_g.InsertBefore($doc.CreateElement('path'), $act_g.FirstChild)
          }
          else {
            $act_g.AppendChild($doc.CreateElement('path'))
          }
     
          $act_x_offset = [System.Math]::Floor($ACTIVATE_WIDTH / 2 * $actLv)
          $act.SetAttribute('class', 'active')
          $act.SetAttribute('d', ('M {0} {1} m -5 0 h 11 V {2} h -11 z' -f ($begin.X + $act_x_offset), $begin.Y, $y))

          #
          if (-not $is_self) {
            if (($begin.Command.Arrow -eq 'CALL') -or ($begin.Command.Description -ne '')) {
              # arrow line
              $node = $seq_g.AppendChild($doc.CreateElement('path'))

              $node.SetAttribute('class', $command.Type.ToLower())
              $node.SetAttribute('d', ('M {0} {1} H {2}' -f $x_from, $y, $x_to))
               
              # arrow head
              $node = $seq_g.AppendChild($doc.CreateElement('path'))
               
              $node.SetAttribute('class', 'head')
              $node.SetAttribute('d', @(
                  ('M {0} {1}' -f ($x_to - $ARROW_WIDTH), ($y - $ARROW_HEIGHT / 2)),
                  ('l {0} {1}' -f $ARROW_WIDTH, ($ARROW_HEIGHT / 2)),
                  ('l {0} {1}' -f (-1 * $ARROW_WIDTH), ($ARROW_HEIGHT / 2)),
                  ('L {0} {1}' -f $x_to, $y)
                ) -join ' ')
               
              if ($x_from -gt $x_to) {
                $node.SetAttribute('transform', ('rotate(180 {0} {1})' -f $x_to, $y))
              }
               
              # arrow description
              if ($command.Description -ne '') {
                $node = $seq_g.AppendChild($doc.CreateElement('text'))
                $node.AppendChild($doc.CreateTextNode($command.Description)) | Out-Null
                    
                $x = if ($x_from -gt $x_to) { $x_to } else { $x_from }
                    
                $node.SetAttribute('x', ($x + 10).ToString())
                $node.SetAttribute('y', ($y - 5).ToString())
              }
            }
            if ($command.Type -eq 'EXIT') {
              # term
              $node = $seq_g.AppendChild($doc.CreateElement('circle'))

              $node.SetAttribute('class', 'term')
              $node.SetAttribute('cx', ($x_to - $TERM_R).ToString())
              $node.SetAttribute('cy', $y.ToString())
              $node.SetAttribute('r', $TERM_R)
            }
          }
        }
        else {
          #
          Write-Debug 'invalid return command.'
        }
     
        #
        $y_count += 1
      }
      #
      'REF' {
        #
        $x_from = [System.UInt32]::MaxValue
        $x_to = [System.UInt32]::MinValue
        $y_from = $Y_START + $Y_OFFSET * $y_count
        $y_to = $y_from + 50

        foreach ($part in $command.Participants) {
          $x = $X_START + $X_OFFSET * $participants[$part].Order
          $x_from = [System.Math]::Min($x_from, $x)
          $x_to = [System.Math]::Max($x_to, $x)
        }

        $x_from -= 50
        $x_to += 50

        $node = $frag_g.AppendChild($doc.CreateElement('path'))

        $node.SetAttribute('class', 'fragment')
        $node.SetAttribute('d', (@(
              ('M {0} {1}' -f $x_from, $y_from),
              ('H {0}' -f $x_to),
              ('V {0}' -f $y_to),
              ('H {0}' -f $x_from),
              ('V {0}' -f $y_from),
              ('h 50 v 15 l -5 5 h -45 z')
            ) -join ' '))

        # fragment
        $text = $frag_g.AppendChild($doc.CreateElement('text'))

        $text.AppendChild($doc.CreateTextNode($command.Type.ToLower())) | Out-Null
        $text.SetAttribute('x', ($x_from + 3).ToString())
        $text.SetAttribute('y', ($y_from + 20 - 3).ToString())

        if ($begin.Command.Description -ne '') {
          $text = $frag_g.AppendChild($doc.CreateElement('text'))

          $text.AppendChild($doc.CreateTextNode('[ ' + $command.Description + ' ]')) | Out-Null
          $text.SetAttribute('x', ($x_from + 10).ToString())
          $text.SetAttribute('y', ($y_from + 20 + 20).ToString())

        }
        #
        $y_count += 2
      }
      #
      'FRAGMENT' {
        #
        $frame_stack += Create_Fragment $command ($Y_START + $Y_OFFSET * $y_count)

        #
        $y_count += 2
      }
      #
      'ELSE' {
        $begin = $frame_stack[-1]

        if ($null -ne $begin) {
          $command.Y = $Y_START + $Y_OFFSET * $y_count
          $begin.Elses += $command
        }
        else {
          Write-Debug 'invalid else fragment.'
        }

        #
        $y_count += 2
      }
      #
      'END' {
        #
        $begin = $frame_stack[-1]

        if ($null -ne $begin) {
          #
          $frame_stack = $frame_stack[0..($frame_stack.Length - 2)]

          #
          $x_from = $begin.MinX - 50
          $x_to = $begin.MaxX + 50
          $y_from = $begin.Y
          $y_to = $Y_START + $Y_OFFSET * $y_count

          # fragment rect
          $node = $frag_g.AppendChild($doc.CreateElement('path'))

          $node.SetAttribute('class', 'fragment')
          $node.SetAttribute('d', (@(
                ('M {0} {1}' -f $x_from, $y_from),
                ('H {0}' -f $x_to),
                ('V {0}' -f $y_to),
                ('H {0}' -f $x_from),
                ('V {0}' -f $y_from),
                ('h 50 v 15 l -5 5 h -45 z')
              ) -join ' '))

          # fragment
          $text = $frag_g.AppendChild($doc.CreateElement('text'))

          $text.AppendChild($doc.CreateTextNode($begin.command.Name)) | Out-Null
          $text.SetAttribute('x', ($x_from + 3).ToString())
          $text.SetAttribute('y', ($y_from + 20 - 3).ToString())

          if ($begin.Command.Description -ne '') {
            $text = $frag_g.AppendChild($doc.CreateElement('text'))

            $text.AppendChild($doc.CreateTextNode('[ ' + $begin.command.Description + ' ]')) | Out-Null
            $text.SetAttribute('x', ($x_from + 10).ToString())
            $text.SetAttribute('y', ($y_from + 20 + 20).ToString())
     
          }

          # else
          foreach ($else in $begin.Elses) {
            # line
            $node = $frag_g.AppendChild($doc.CreateElement('path'))

            $node.SetAttribute('class', 'else')
            $node.SetAttribute('d', ('M {0} {1} H {2}' -f $x_from, $else.Y, $x_to))

            # text
            if ($else.Description -ne '') {
              $text = $frag_g.AppendChild($doc.CreateElement('text'))

              $text.AppendChild($doc.CreateTextNode('[ ' + $else.Description + ' ]')) | Out-Null
              $text.SetAttribute('x', ($x_from + 10).ToString())
              $text.SetAttribute('y', ($else.Y + 20).ToString())
            }
          }
        }
        else {
          #
          Write-Debug 'invalid pair command of end.'
        }

        #
        $y_count += 1
      }
    }
  }

  ##
  $doc.Save($arg + '.htm')
}
