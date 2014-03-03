
import processing.serial.*;

static final int SM_CMD_MAX_STEPS = 32000; // really 32767

//-----------------------------------------------------------------------------
class MotorController
{
  Serial _port;

  boolean _dryRun = false;
  boolean _stopped = false;
  boolean _plotMode = false;
  boolean _resumeMode = false;
  int _resumeMode_penState = 0;
  int _resumeMode_commandCount = 0;

  int _penState = 0;
  int _commandCount = 0;

  float _spoolDiameter = 10;  // diameter of where the string wraps up in mm
  float _spoolCircumference = _spoolDiameter * PI; // distance around spool in mm
  
  float _machineWidth = 625; // eyelet to eyelet distance in mm
  float _machineHeight = 600.0; // used in the draw routine

  float _penOffsetY = 15;  // in mm, x distance from pen center to string connection point on gondola
  float _penOffsetX = 30;  // in mm, y distance from pen center to string connection point on gondola

  int _motorStepsPerRev = 3200; // 200 step / rev motor using
                                // EggBot board 16 micro steps setting
                                // Adjust for different microsteps
  //int _motorTimePerRevPenUp = 250;//1000; // ms per rev.
  //int _motorTimePerRevPenDown = 500;//1000; // ms per rev.
  float _motorSpeedPenUp = 15.0; // mm/s   (was 5)
  float _motorSpeedPenDown = 15.0; // mm/s  ( was 5)
  float _motorSpeedSetup = 5.0; // mmm/s
  int _motorA_Dir = 1;
  int _motorB_Dir = -1;
  float _setupMoveMotorsStepSize = 16.0; 

  // these are the pen up/pen down positions.
  // NOTE: servo rotation is dependent on brand!
  int _servoPosUp = 16300;
  int _servoPosDown = 10000;
  int _servoRateDown = 600; // was 300
  int _servoRateUp = 600; // was 300

    // in mm
  float _homePosY = 0;
  PVector _homeAB = new PVector(0, 0); // A and B are the cord lengths from the spool to the gondola connections
                                        // Use a PVector because it is a tuple.  
                                        // PVector.x holds A and Pvector.y holds B

  // in steps, always positive line length
  // Maintain the count of motor steps for A and B.
  // Used to calculate the amount of line spooled out
  // on each motor.
  int _deltaStepsA;
  int _deltaStepsB;
  PVector _currentPos = new PVector(0, 0); // cached because we can't yet calculate from A,B
  PVector _plotPos = new PVector(0, 0);

  // stats
  int _statsPenUpDuration = 0; // time spent with pen up, including pen up/down transitions
  int _statsPenDownDuration = 0; // time spent plotting with pen down
  float _statsPenUpDistance = 0; // distance spent moving with pen up
  float _statsPenDownDistance = 0; // distance spent moving with pen down

  PVector _preDryRun_currentPos;
  int _preDryRun_deltaStepsA;
  int _preDryRun_deltaStepsB;
  int _preDryRun_penState;
  PApplet myApplet;

//-----------------------------------------------------------------------------
  MotorController( PApplet applet )
  {
    myApplet = applet;
  }

//-----------------------------------------------------------------------------
void init(String portName)
{
    // Can't work out how to get error result from Serial.
    // Only open portName if it is in the list of ports.
    for( int i = 0; i < Serial.list().length; i++ )
    {
      println(Serial.list()[i]);
      if ( Serial.list()[i].equals( portName ) )
      {
        _port = new Serial(myApplet, portName, 9600);
      }
    }

    setServoSettings();

    // force pen up
    _penState = 0;
    penUp();

    setHome( 250.0 );
}

//-----------------------------------------------------------------------------
  void startDryRun()
  {
    _dryRun = true;

    _preDryRun_currentPos = _currentPos.get();
    _preDryRun_deltaStepsA = _deltaStepsA;
    _preDryRun_deltaStepsB = _deltaStepsB;
    _preDryRun_penState = _penState;

    _statsPenUpDuration = 0;
    _statsPenDownDuration = 0;
    _statsPenUpDistance = 0;
    _statsPenDownDistance = 0;
  }

//-----------------------------------------------------------------------------
  void endDryRun()
  {
    _dryRun = false;

    _currentPos = _preDryRun_currentPos.get();
    _plotPos = _preDryRun_currentPos.get();
    _deltaStepsA = _preDryRun_deltaStepsA;
    _deltaStepsB = _preDryRun_deltaStepsB;
    _penState = _preDryRun_penState;
  }

//-----------------------------------------------------------------------------
  void startPlot()
  {
    if ( ! _dryRun )
    {
      // query button state to ignore presses before plot starts
      sendCommand( "QB\r" );
    }
    _plotMode = true;
    _stopped = false;
    _commandCount = 0;   
    // _resumeMode might be true or false
  }

//-----------------------------------------------------------------------------
  void endPlot()
  {
    _plotMode = false;
    _stopped = false;
    _commandCount = 0;
    _resumeMode = false;
  }

//-----------------------------------------------------------------------------
// The point p is the tip of the pen.
// A and B are the string lengths from the spool to the 
// connection points on the gondola.  Offset the
// the calculations by the XY pen to AB connection
// points on the gondola
//
// This math assumes the two vectors A and B (representing
// the strings from motor A and motor B) meet at the intersection
// of the A and B vectors.  The pen is actually farther down in
// the gondola and below the intersection point.
// Use the pen Y offset in the gondola to figure out the 
// Y value of the pen position XY to calculate the cord 
// lengths A and B.
// 
  PVector XYtoAB( PVector p )
  {
      // points p0 and p1 are the string connection points on the 
      // gondola of strings A and B
      PVector p0 = new PVector( p.x - _penOffsetX, p.y - _penOffsetY );
      PVector p1 = new PVector( p.x + _penOffsetX, p.y - _penOffsetY );
      // point (0,0) is the eyelet point of string A
      // point (_machineWidth,0) is the eyelet of string B
      float a = dist( 0, 0, p0.x, p0.y );
      float b = dist( _machineWidth, 0, p1.x, p1.y );
      return new PVector( a, b ); // return a tuple with p.x as A and p.y as B
  }

//-----------------------------------------------------------------------------
// Calculate the XY position of the pen based on the length of the cords 
// A and B.  Calculation takes into account the connection points on the gondola
// not being coincident.  
// PVector p contains the two lengths A and B as p.x and p.y
  PVector ABtoXY( PVector p )
  {
    float a = p.x;  // get the string length A and B
    float b = p.y;
    //float w = _machineWidth;
    // f is the base of the triangle with the width of the
    // gondola connection points in X subtracted out.
    // a^2 = x^2 + y^2
    // b^2 = (f-x)^2 + y^2
    // b^2 = f^2 -2fx +x^2 + y^2
    // a^2 - x^2 = y^2
    // b^2 - f^2 -x^2 + 2fx = y^2
    // a^2 -x^2 = b^2 - f^2 - x^2 + 2fx
    // a^2 - b^2 + f^2 = 2fx
    // x = (a^2 - b^2 +f^2 ) / 2f
    float f = _machineWidth - (2*_penOffsetX);
    //float x = ( w*w - b*b + a*a ) / ( 2*w );
    float x = ( f*f - b*b + a*a ) / ( 2*f ); // 
    float y = sqrt( a*a - x*x ); // right triangle x,y,a.  x^2 + y^2 = a^2
    return new PVector( x + _penOffsetX, y + _penOffsetY );
  }

//-----------------------------------------------------------------------------
  void _delay( int duration )
  {
    try
    {
      Thread.sleep(duration);
    }
    catch (InterruptedException e) 
    {
    }
  }

//-----------------------------------------------------------------------------
// Send the command string to the control board.
// Assumption is command is in the format required for the controller.
// For the EggBotBoard the commands must end with a LF+CR or a
// combination of either or both.
// Try to read response up to 20 times, delaying 50 msec between each check.
// Look for a trailing newline to indicate response received.
// Compare the response to OK and return null on only OK found
// Return response captured without the trailing (or not trailing) OK
//
// Some EBB commands just return OK<cr><lf> --> sendCommand returns null
// Some return just data followed by <cr><lf> --> sendCommand returns ???
// Some return data followed by <cr><lf> and then OK followed by <cr><lf>
// The QB (query button) command returns a 0 or 1 <cr><lf> OK<cr><lf>
// This function returns null on JUST OK received
// Returns non null and the non-OK part of the response
// for all other cases, data only, data+ok
//
// Loop up to 20 times with 50 msec delay between each loop 
// looking for the OK<cr><lf>
// If the EBB command only returns data and not a trailing OK
// like the version command, this function will take the full
// 20 x 50 msec to time out and eventually return the 
// captured version data.
// If the EBB command returns data and then an OK, such as
// the QB command (data<cr><lf>OK<cr><lf>) this routine
// will end quickly when it finds the OK and will return
// the previously found response ( the data )
//
  String sendCommand( String command )
  {
    println("<<"+command+">>");
    debugTextarea.append("<<"+command+">>\n").scroll(1);
    
    if ( _dryRun )
    {
      return null;
    }

    String response = null;
    if ( _port != null )
    {
      _port.write(command);

      String s;
      for( int i = 0; i < 20; i++ )
      {
        // EBB returns <cr><lf> at the end of each response
        s = _port.readStringUntil('\n');
        if ( s != null )
        {
          // trim off trailing "\r\n"
          s = s.substring( 0, s.length()-2 );

          // compareTo returns 0 if strings are equal
          if ( s.compareTo("OK")==0 )
          {
            // if the OK was returned from the EBB
            // then return whatever has been captured prior to the OK
            // which might be null for only OK responses
            return response;
          }
          else
          {
            // if response was not "OK" then capture that
            println("rsp: "+s);
            debugTextarea.append("rsp: "+s+"\n").scroll(1);
            response = s;
          }
        }
        // loop again looking for OK
        _delay(50);
      }
    }

    return response;
  }

//-----------------------------------------------------------------------------
// Query the push button on the eggbot board.
  void queryButton()
  {
    if ( _dryRun )
    {
      return;
    }

    String response = sendCommand( "QB\r" );
    if ( response != null && response.compareTo("1")==0 )
    {
      _stopped = true;
      _resumeMode_commandCount = _commandCount;
      _resumeMode_penState = _penState;
      println("stopped after command "+_resumeMode_commandCount+" at "+_currentPos.x+","+_currentPos.y+" pen="+_resumeMode_penState );
    }
  }

//-----------------------------------------------------------------------------
// Settings for the Pen Servo.
// Set servo control values (pulse width) for the servo up and down positions.
// The servo rate up and down settings control how much the servo position
// is modified each pass through the servo update internal to the eggbot.
// The default settings for the eggbot board are 8 servo channels each updated
// at 3 msecs per channel, or 24 msec for a full loop through all 8 channels.
  void setServoSettings()
  {
    // NOTE: EBB command doco reads: "SC,4,<servo_min>" and "SC,5,<servo_max>" 
    // BAD NAMING! Really should be called <servo_pos_up> <servo_pos_down>
    // since pen up command moves servo to <servo_min> at <servo_rate_up>
    // pen down command moves servo to <servo_max> at <servo_rate_down>
    sendCommand( "SC,4," + _servoPosUp + "\r");
    sendCommand( "SC,5," + _servoPosDown + "\r");
    // sendCommand( "SC,10," + min(_servoRateUp,_servoRateDown) + "\r");
    sendCommand( "SC,11," + _servoRateUp + "\r");
    sendCommand( "SC,12," + _servoRateDown + "\r");
  }

//-----------------------------------------------------------------------------
  PVector getHome()
  {
    return new PVector( _machineWidth/2, _homePosY );
  }

//-----------------------------------------------------------------------------
  void setHome( float y )
  {
    _homePosY = y;
    _homeAB = XYtoAB( getHome() );
    _currentPos.set( getHome() );
    _plotPos.set( getHome() );

    println("_homeAB="+_homeAB.x + "," + _homeAB.y );

    _deltaStepsA = 0;
    _deltaStepsB = 0;
  }

//-----------------------------------------------------------------------------
  PVector getCurrentAB()
  {
    return new PVector( _homeAB.x + ( _deltaStepsA * ( _spoolCircumference / _motorStepsPerRev ) ), 
    _homeAB.y + ( _deltaStepsB * ( _spoolCircumference / _motorStepsPerRev ) ), 0 );
  }

//-----------------------------------------------------------------------------
  // The calculated position of the pen based on changed line lengths
  // which were rounded to nearest step.
  PVector getCurrentXY()
  {
      return ABtoXY( getCurrentAB() );
  }

//-----------------------------------------------------------------------------
// Send the pen servo move command.  
// Delay any new commands until at least a calculated delay.
// Calculate delay based on servo range divided by servo rate.
// The * 24 is for the 3 msec / channel times 8 channels = 24 msec
// ??? Why multiply by the 24 msec?  Because the servo rate is per
// channel ??
  void penUp()
  {
    if ( _stopped || _resumeMode )
    {
      return;
    }

    if ( _penState == 0 )
    {
      int duration = round( (float)(abs(_servoPosUp - _servoPosDown)) / (float)_servoRateUp ) * 24;
      // This doesn't work for large durations.
      //sendCommand("SP,1," + duration + "\r");
      sendCommand("SP,1\r");
      // Do it the EggBot Inkscape plugin way.
      delayMotors( duration );
      _penState = 1;

      _statsPenUpDuration += duration;
    }
  }

//-----------------------------------------------------------------------------
// Send the pen servo move command.  
// Delay any new commands until at least a calculated delay.
// Calculate delay based on servo range divided by servo rate.
// The * 24 is for the 3 msec / channel times 8 channels = 24 msec
// ??? Why multiply by the 24 msec?  Because the servo rate is per
// channel ??
  void penDown()
  {
    if ( _stopped || _resumeMode )
    {
      return;
    }

    if ( _penState == 1 )
    {
      int duration = round( (float)(abs(_servoPosUp - _servoPosDown)) / (float)_servoRateDown ) * 24;
      // This doesn't work for large durations.
      //sendCommand("SP,0," + duration + "\r");
      sendCommand("SP,0\r");
      // Do it the EggBot Inkscape plugin way.
      delayMotors( duration );
      _penState = 0;

      _statsPenUpDuration += duration;
    }
  }

//-----------------------------------------------------------------------------
// Tell the eggbot board to not initiate the next command 
// until after delay has elapsed.
// The SM (stepper move) command with 0 for x and y just delays the next
// command for duration.
  void delayMotors( int duration )
  {
    // Code copied from EggBot Inkscape plugin.
    // I assume "SM" command doesn't like duration more than 750ms
    // when steps are zero.
    while ( duration > 0 )
    {
      int d = min(duration, 750);
      sendCommand("SM,"+d+",0,0\r");
      duration -= d;
    }
  }


//-----------------------------------------------------------------------------
  void lineTo( float x, float y )
  {
    lineTo( new PVector( x, y ) );
  }

//-----------------------------------------------------------------------------
// Move the pen in a line made up of N segments
// Does not manipulate the pen, pen must be in the correct state, up or down,
// before the line drawn (or not drawn).
  void lineTo( PVector pt )
  {
    // inelegant first draft
    // just divide into 1mm segments

    // must copy _plotPos because it gets updated during moveTo()
    PVector startPt = _plotPos.get();
    PVector endPt = pt;

    float segmentLength = 2.0;
    float lineLength = dist(startPt.x, startPt.y, endPt.x, endPt.y );
    int steps = ceil( lineLength / segmentLength ); // round up
    //println( "lineTo(): lineLength=" + lineLength + " steps=" + steps );


    for ( int i=1; i<=steps; i++ )
    {
      float amt = (float)i / (float)steps;

      // linear interpolation between start and end points
      float x = lerp( startPt.x, endPt.x, amt );
      float y = lerp( startPt.y, endPt.y, amt );

      moveTo( x, y );
    }
  }

//-----------------------------------------------------------------------------
  void moveToHome()
  {
    moveTo( getHome() );
  }

//-----------------------------------------------------------------------------
  void moveTo( float x, float y )
  {
    moveTo( new PVector( x, y ) );
  }

//-----------------------------------------------------------------------------
  void moveTo( PVector pt )
  {
    if ( _stopped )
    {
      return;
    }

    // we are doing the nth command now.
    _commandCount++;
    _plotPos = pt.get();

    if ( _resumeMode && _commandCount < _resumeMode_commandCount )
    {
      //println("resume mode ("+_resumeMode_commandCount+"): skipping command "+_commandCount+" moveTo "+pt.x+","+pt.y);
      return;
    }

    if ( _resumeMode )
    {
      //println("resume mode ("+_resumeMode_commandCount+"): executing command "+_commandCount+" moveTo "+pt.x+","+pt.y);
    }
    else
    {
      //println("executing command "+_commandCount+" moveTo "+pt.x+","+pt.y);
    }

    PVector newAB = XYtoAB( pt );
    PVector currentAB = getCurrentAB();
    PVector currentXY = getCurrentXY(); // NB: this is the REAL position of the pen, different to _plotPos

    int stepsA = round( ( newAB.x - currentAB.x ) / ( _spoolCircumference / _motorStepsPerRev ) );
    int stepsB = round( ( newAB.y - currentAB.y ) / ( _spoolCircumference / _motorStepsPerRev ) );

    float speed = ( _penState == 0 ) ? _motorSpeedPenDown : _motorSpeedPenUp;
    float distance = dist( currentXY.x, currentXY.y, pt.x, pt.y );
    int duration = round( distance / speed * 1000.0);
    //println("moveTo: _penState="+_penState+" distance="+distance+" speed="+speed+" duration="+duration);
    moveMotors( stepsA, stepsB, duration, /*updateDeltaSteps=*/ true );
    // cache the REAL position of the pen (because we can't calc it from A,B just yet)
    _currentPos = pt.get();

    if ( _penState == 0 )
    {
      _statsPenDownDuration += duration;
      _statsPenDownDistance += distance;
    }
    else
    {
      _statsPenUpDuration += duration;
      _statsPenUpDistance += distance;
    }

    // we resume by re-doing the last move command before stopping, and then resetting pen state
    // to what it was at the time of stopping.
    if ( _resumeMode && _commandCount == _resumeMode_commandCount )
    {
      //println("resume mode ("+_resumeMode_commandCount+"): after command "+_commandCount+" moveTo "+pt.x+","+pt.y+" pen="+_resumeMode_penState);
      _resumeMode = false;
      if ( _resumeMode_penState == 0 )
      {
        //println("pen down to resume");
        penDown();
      }
      // in theory, we're now out of resume mode state and could just
      // set _resumeMode to false.
    }

    if ( _plotMode )
    {   
      queryButton();
    }
  }

//-----------------------------------------------------------------------------
  void setSetupMoveMotorStepSize( float setupMoveMotorsStepSize )
  {
    _setupMoveMotorsStepSize = setupMoveMotorsStepSize;
  }

//-----------------------------------------------------------------------------
  void setupMoveMotors( float directionA, float directionB )
  {
    // HACK: args in steps, convert to distance
    float distanceA = directionA * _setupMoveMotorsStepSize * ( _spoolCircumference / _motorStepsPerRev );
    float distanceB = directionB * _setupMoveMotorsStepSize * ( _spoolCircumference / _motorStepsPerRev );
    int stepsA = round( distanceA / ( _spoolCircumference / _motorStepsPerRev ) );
    int stepsB = round( distanceB / ( _spoolCircumference / _motorStepsPerRev ) );

    float speed = _motorSpeedSetup;
    float distance = max( abs(distanceA), abs(distanceB) );
    int duration = round( distance / speed * 1000.0);

    moveMotors( stepsA, stepsB, duration, /*updateDeltaSteps=*/ false );
  }

//-----------------------------------------------------------------------------
  // this handles steps greater than the maximum steps per motor move command.
  // also will do nothing if both step values are zero
  void moveMotors( int stepsA, int stepsB, int duration, boolean updateDeltaSteps )
  {
    int totalStepsA = stepsA;
    int totalStepsB = stepsB;
    int totalDuration = duration;
    while ( (totalStepsA != 0 || totalStepsB != 0) )
    {
      stepsA = totalStepsA;
      stepsB = totalStepsB;
      duration = totalDuration;

      float f = 1.0;
      if ( abs(stepsA) > SM_CMD_MAX_STEPS || abs(stepsB) > SM_CMD_MAX_STEPS )
      {
        f = (float)SM_CMD_MAX_STEPS / abs((float)max(abs(stepsA), abs(stepsB)));
      }

      // avoid all possibility of float math causing value to exceed actual maximum
      stepsA = constrain( round(f * stepsA), -SM_CMD_MAX_STEPS, SM_CMD_MAX_STEPS );
      stepsB = constrain( round(f * stepsB), -SM_CMD_MAX_STEPS, SM_CMD_MAX_STEPS );
      duration = constrain( round(f * duration), 1, 65535 );

      sendCommand("SM," + duration + "," + _motorA_Dir*stepsA + "," + _motorB_Dir*stepsB + "\r" );

      //float rpsA = (float)stepsA / ((float)duration / 1000.0) / (float)_motorStepsPerRev;
      //float rpsB = (float)stepsB / ((float)duration / 1000.0) / (float)_motorStepsPerRev;
      //PVector currentXY = getCurrentXY();
      //PVector newXY = ABtoXY( new PVector( getCurrentAB().x + (float)stepsA/(float)_motorStepsPerRev*(float)_spoolCircumference,
      //                                    getCurrentAB().y + (float)stepsB/(float)_motorStepsPerRev*(float)_spoolCircumference ) );
      //float speed = dist(currentXY.x, currentXY.y, newXY.x, newXY.y) / ((float)duration/1000.0);
      //println("speedA="+ rpsA*_spoolCircumference +"mm/s speedB=" + rpsB*_spoolCircumference + "mm/s speed="+speed+"mm/s");

      // totalStepsA,totalStepsB will approach zero.
      totalStepsA -= stepsA;
      totalStepsB -= stepsB;
      totalDuration -= duration;

      // track total change in motor position.
      // this is the source of current actual position of pen
      if ( updateDeltaSteps )
      {
        _deltaStepsA += stepsA;
        _deltaStepsB += stepsB;
      }
    }
  }

//-----------------------------------------------------------------------------
// Draw a circle by drawing multiple straight line segments.
// Assumes this function is called with the pen up.
// Input the center and radius of the circle.
  void circle( PVector pt, float radius )
  {
    float segmentLength = 1.0;
    float circumference = PI * 2.0 * radius;
    int steps = ceil( circumference / segmentLength ); // round up
    
    // use a minimum of 8 line segments to make the circle
    if ( steps < 8 )
    {
      steps = 8;
    }

    // if the radius is 0 or smaller just move the
    // pen to the center point and drop the pen
    if ( radius <= 0 )
    {
      moveTo( pt.x, pt.y );
      penDown();
    }
    else
    {
      // run the for loop for <= to steps to get the starting
      // point at zero angle and then get all of the rest of the steps
      // around the circle.
      for ( int i=0; i<=steps; i++ )
      {
        // divide a circle (2*PI) by the number of steps
        // and get each angle around the circle
        float angle = ((float)i / (float)steps) * 2.0 * PI;

        // calculate the x,y position of the point
        // to move to.  First calculated point is with
        // i = 0 so the angle will be zero.
        // Start the circle at radius r and angle 0
        float x = pt.x + cos( angle ) * radius;
        float y = pt.y - sin( angle ) * radius;

        // move to the newly calculated point
        // The first point is at angle 0
        // move to radius r at angle 0 and drop the pen 
        moveTo( x, y );
        penDown();
      }
    }
  }

//-----------------------------------------------------------------------------
// Draw a filled circle by drawing repeated cicles within cicles
// each cicle is smaller than the previous by penWidth
// Input the center and radius of the circle.
  void fillCircle( PVector pt, float radius, float penWidth )
  {
    float r = radius;
    while ( r >= 0 )
    {
      circle( pt, r ); // draw a cicle
      r -= penWidth;
    }
    moveTo( pt.x, pt.y ); // move to the center of the circle
  }
}

