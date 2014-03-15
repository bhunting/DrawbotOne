/*************************************************
 * Drawbot code to drive a polar graphic plotter.
 * MotorController is presently coded to support the
 * EiBotBoard (EggBotBoard) from Brian Schmalz 
 * http://www.schmalzhaus.com/EBB/
 *
 * Original code is from Wilba6582 (Jason Williams) and is
 * released with the copyright
 * "I hereby release that source code package as Creative Commons blah blah free for anyone to use for any purposes."
 *
 * Modifications by Brad Hunting released under a Creative Commons Attribution 4.0 International License.
 *
 * Released files include DrawbotWilba.pde, MotorController.pde, ShapeManager.pde
 *
 ************************************************/

import java.awt.event.*;
import controlP5.*;

ControlP5 cp5;
Textarea debugTextarea;
Println debugConsole;
DropdownList _dlCommPorts;
String commPort = "";

// offset in screen space to plotter workspace
// set below to corner of plotter space in the screen space
PVector _screenTranslate = new PVector(0, 0);
float _screenScale = 1; // scale of plotter space in screen space

PVector _mouse = new PVector(0, 0);
PVector _mousePress = null;

PVector _lineStart = new PVector(0, 0);
PVector _lineEnd = new PVector(0, 0);

int _displaySizeX = 800;
int _displaySizeY = 900;
int _guiHeight = 200;
int _plotHeight = _displaySizeY - _guiHeight;
String _imageFilePath = "";
boolean _guiInitialized = false;

MotorController _motorController;
ShapeManager _shapeManager = new ShapeManager();
RPoint[][] _shapePoints;

PImage _image; // processing class for loading and describing bitmap images
float _imageScale = 1; // pixels per mm ??
int _imageOffsetX = 0;
int _imageOffsetY = 0;
float _pageOffsetY = 0;
PVector _pageSizeA4 = new PVector( 210, 297 ); // A4 portrait
PVector _pageSize = new PVector( _pageSizeA4.x, _pageSizeA4.y ); // A4 portrait
PVector _pageUpperLeft = new PVector( 100, 100 );
PVector _pageLowerRight = new PVector( _pageUpperLeft.x + _pageSize.x, _pageUpperLeft.y+_pageSize.y); 
PVector _shapeOffset = new PVector(0, 0);

boolean _showImage = true;
boolean _showProcessedImage = true;

int _stepsPerClick = 1;

//-----------------------------------------------------------------------------
void setup()
{
  size(_displaySizeX, _displaySizeY );

  // VERY IMPORTANT: Allways initialize the library before using it
  RG.init(this);

  // Create MotorController before GUI
  // then controls can be init with values
  _motorController = new MotorController(this);

  cp5 = new ControlP5(this);
  cp5.enableShortcuts();
  setupGUI();

  _motorController.init("COM20");
  setupGamepad();

  addMouseWheelListener(new MouseWheelListener() 
                        { public void mouseWheelMoved(MouseWheelEvent mwe) 
                             { mouseWheel(mwe.getWheelRotation()); } } ); 

  // scale working space into screen space
  _screenScale = 1.0;
  _screenTranslate.set( (_displaySizeX - _motorController._machineWidth*_screenScale)/2, 40, 0 ); // center machine width in the screen space

  _lineStart = _motorController.getCurrentXY().get();
  _lineEnd = _motorController.getCurrentXY().get();

  _pageOffsetY = 0;

  //_shapeManager.loadShape("test1.svg");
  //_shapeOffset.set( 30, 50, 0 );

//  _image = loadImage( "freckles.jpg" );
//  _imageScale = 0.195;
  //_imageScale = 0.5;
//  _shapeManager.rasterizeImage( _image, _imageScale );
  _shapeOffset.set( 0, 0, 0 );

  PVector home = _motorController.getHome();
  _pageUpperLeft.x = home.x - (_pageSize.x/2);
  _pageUpperLeft.y = home.y + _pageOffsetY;
  _pageLowerRight.x = _pageUpperLeft.x + _pageSize.x;
  _pageLowerRight.y = _pageUpperLeft.y + _pageSize.y; 
}

//-----------------------------------------------------------------------------
PVector screenToModel( PVector p )
{
  float x = p.x;
  float y = p.y;
  x -= _screenTranslate.x;
  y -= _screenTranslate.y;
  x *= 1.0/_screenScale;
  y *= 1.0/_screenScale;
  return new PVector(x, y);
}

//-----------------------------------------------------------------------------
PVector modelToScreen( PVector p )
{
  float x = p.x;
  float y = p.y;
  x *= _screenScale;
  y *= _screenScale;
  x += _screenTranslate.x;
  y += _screenTranslate.y;
  return new PVector(x, y);
}

//-----------------------------------------------------------------------------
PVector getPageOrigin()
{
  //PVector home = _motorController.getHome();
  //return new PVector( home.x - (_pageSize.x/2), home.y + _pageOffsetY );
  return new PVector( _pageUpperLeft.x, _pageUpperLeft.y );
}

//-----------------------------------------------------------------------------
PVector getShapeOrigin()
{
  PVector pageOrigin = getPageOrigin();
  return new PVector( pageOrigin.x + _shapeOffset.x + _imageOffsetX, pageOrigin.y + _shapeOffset.y + _imageOffsetY );
}

//-----------------------------------------------------------------------------
void draw()
{
  background(220,220,220,128);
  // draw a rectangle around the gui area
  fill(140);
  stroke(0);
  rect( 0, _displaySizeY-_guiHeight, _displaySizeX, _displaySizeY );


  pushMatrix();
  {
    // draw a rectangle of the working space of the drawbot - the pen reach
    // translate the drawing from screen space into plotter space, offset and scale
    translate(_screenTranslate.x, _screenTranslate.y);
    scale(_screenScale);

    // draw a filled rectangle representing the 
    // outline of the plotter workspace
    fill(168);
    stroke(0);
    rect( 0, 0, _motorController._machineWidth, _motorController._machineHeight );

    // draw the paper surface
    pushMatrix();
    {
      // draw the paper footprint
      // get the paper origin and translate the
      // drawing space into the paper space
      PVector pageOrigin = getPageOrigin();
      translate(pageOrigin.x, pageOrigin.y);

      fill(255);
      strokeWeight(1/_screenScale); // set line thickness
      stroke(0);                    // set border (outline) color
      rect( 0, 0, _pageSize.x, _pageSize.y ); // draw the paper
    }
    popMatrix();

    // paint the original image, tint it as partially see through
    if( _showImage )
    {
      pushMatrix();
      {
        if ( _image != null )
        {
          PVector shapeOrigin = getShapeOrigin();
          translate(shapeOrigin.x, shapeOrigin.y);
          scale( _imageScale );
          tint(255, 255, 255, 30);
          image( _image, 0, 0 );
          noTint();
        }
      }
      popMatrix();
    }

    // Draw the little X at HOME at the top of the paper
    PVector home = _motorController.getHome();
    noFill();
    strokeWeight(1/_screenScale);
    stroke(0);
    float n = 5;
    line( home.x-n, home.y-n, home.x+n, home.y+n );
    line( home.x+n, home.y-n, home.x-n, home.y+n );

    // Draw the spools in the upper left and upper right
    PVector motorA = new PVector( 0, 0 );
    PVector motorB = new PVector( _motorController._machineWidth, 0 );
    float spoolRadius = _motorController._spoolDiameter/2;

    strokeWeight(1/_screenScale);
    noFill();

    stroke(#0000FF);
    ellipse( motorA.x - spoolRadius, motorA.y, 2*spoolRadius, 2*spoolRadius );
    stroke(#00FF00);
    ellipse( motorB.x + spoolRadius, motorB.y, 2*spoolRadius, 2*spoolRadius );

    // draw a line and arc from the motor spool to the starting point
    // draw a line and arc from the motor spool to the ending point
    // starting and ending points can be set by clicking the mouse
    // or by click-dragging the mouse to set start and end

    // draw the A (left) side line and arc representing the string
    stroke(#0000FF);
    line( motorA.x, motorA.y, _lineStart.x, _lineStart.y );
    line( motorA.x, motorA.y, _lineEnd.x, _lineEnd.y );
    float r;
    r = dist( motorA.x, motorA.y, _lineStart.x, _lineStart.y );
    //ellipse( motorA.x, motorA.y, 2*r, 2*r );
    arc( motorA.x, motorA.y, 2*r, 2*r, 0, PI/2 );
    r = dist( motorA.x, motorA.y, _lineEnd.x, _lineEnd.y );
    //ellipse( motorA.x, motorA.y, 2*r, 2*r );
    arc( motorA.x, motorA.y, 2*r, 2*r, 0, PI/2 );

    // draw the B (right) side line and arc representing the string
    stroke(#00FF00);
    line( motorB.x, motorB.y, _lineStart.x, _lineStart.y );
    line( motorB.x, motorB.y, _lineEnd.x, _lineEnd.y );
    r = dist( motorB.x, motorB.y, _lineStart.x, _lineStart.y );
    //ellipse( motorB.x, motorB.y, 2*r, 2*r );
    arc(  motorB.x, motorB.y, 2*r, 2*r, PI/2, PI );
    r = dist( motorB.x, motorB.y, _lineEnd.x, _lineEnd.y );
    //ellipse( motorB.x, motorB.y, 2*r, 2*r );
    arc(  motorB.x, motorB.y, 2*r, 2*r, PI/2, PI );

    // draw a line between the start and end points
    // show the pen path
    stroke(#FF0000);
    line( _lineStart.x, _lineStart.y, _lineEnd.x, _lineEnd.y );

    /*
    // Draw a 10 segment lerp arc between start and end points
    //
    
    stroke(#FF00FF);
     
    PVector motorStart = _motorController.XYtoAB( _lineStart );
    PVector motorEnd = _motorController.XYtoAB( _lineEnd ); 
     
    noFill();
    beginShape();
    {
       for ( int i=0; i<=10; i++ )
       {
         float t = (float)i / 10.0;
         
         float mx = lerp( motorStart.x, motorEnd.x, t );
         float my = lerp( motorStart.y, motorEnd.y, t );
         
         PVector p = new PVector( mx, my );
         p = _motorController.ABtoXY( p );
         vertex( p.x, p.y );
       }
    }
    endShape();
    */
  }
  popMatrix();


  // draw the processed image
  if( _showProcessedImage )
  {
    pushMatrix();
    {
      translate(_screenTranslate.x, _screenTranslate.y);
      scale(_screenScale);
  
      RG.ignoreStyles();
  
      noFill();
      strokeWeight(1/_screenScale);
      stroke(0);
  
      if ( _shapeManager.getPlotShape() != null )
      {
        pushMatrix();
        PVector shapeOrigin = getShapeOrigin();
        translate(shapeOrigin.x, shapeOrigin.y);
        _shapeManager.getPlotShape().draw();
        popMatrix();
  
        if ( _shapePoints == null )
        {
          _shapePoints = _shapeManager.getPointsInPaths( _shapeManager.getPlotShape(), shapeOrigin );
        }
        //drawShapePoints(_shapePoints);
      }
    }
    popMatrix();
  }
}

//-----------------------------------------------------------------------------
void drawShapePoints( RPoint[][] shapePoints )
{
  if ( shapePoints == null )
  {
    return;
  }
  RPoint lastPoint = null;
  for ( int n=0; n<shapePoints.length; n++ )
  {
    RPoint[] points = shapePoints[n];


    // If there are any points
    if (points != null)
    {
      if ( lastPoint != null )
      {
        noFill();
        stroke(192, 192, 255);
        strokeWeight(1/_screenScale);
        if ( false )/*drawPenUpMoves*/
          line(lastPoint.x, lastPoint.y, points[0].x, points[0].y);
      }

      noFill();
      stroke(0, 0, 255);
      strokeWeight(1/_screenScale);
      beginShape();
      for (int i=0; i<points.length; i++)
      {
        if ( false )/*drawPenDownMoves*/
          vertex(points[i].x, points[i].y);
      }
      endShape();


      fill(0);
      stroke(255, 0, 0);
      strokeWeight(3/_screenScale);
      for (int i=0; i<points.length; i++)
      {
        if ( true )/*drawNodes*/
          point(points[i].x, points[i].y);
      }

      lastPoint = points[points.length-1];
    }
  }
}

//-----------------------------------------------------------------------------
void mousePressed()
{
  if ( mouseY > height-_guiHeight )
  {
    // ignore mouse presses in GUI area
    return;
  }

  _mouse.set( mouseX, mouseY, 0);
  _mousePress = new PVector(mouseX, mouseY);

  if ( mouseButton==LEFT)
  {
    _lineStart = screenToModel(_mouse);
    _lineEnd = _lineStart;
  }

  if ( mouseButton==RIGHT )
  {
  }
}

//-----------------------------------------------------------------------------
void mouseReleased()
{
  if ( mouseButton==LEFT && _mousePress != null )
  {
    _motorController.penUp();
    _motorController.moveTo( _lineStart );
    if ( _lineStart.x != _lineEnd.x || _lineStart.y != _lineEnd.y )
    {
      _motorController.penDown();
      _motorController.lineTo( _lineEnd );
      _motorController.penUp();


      /*
       float x = _lineStart.x;
       float y = _lineStart.y;
       float r = 0.1;
       for ( int i=1; i<=10; i++ )
       {
         _motorController.fillCircle( new PVector(x,y), r, 0.4 );
         _motorController.penUp();
         x += 3*r+2;
         r += 0.1;
       }
       */
    }
  }
  _mousePress = null;
}

//-----------------------------------------------------------------------------
void mouseDragged()
{
  if ( _mousePress == null )
  {
    // ignore drags starting in the GUI area
    return;
  }

  PVector newMouse = new PVector( mouseX, mouseY );
  if ( mouseButton == LEFT && mouseY <= height-_guiHeight )
  {
    _lineEnd = screenToModel(newMouse);
  }

  if ( mouseButton==CENTER )
  {
    _screenTranslate.set( _screenTranslate.x + (newMouse.x - _mouse.x), _screenTranslate.y + (newMouse.y - _mouse.y), 0 );
  }

  _mouse = newMouse;
}

void mouseWheel(int delta)
{
//  PVector oldMouse = screenToModel( new PVector(mouseX, mouseY) );
//  _screenScale *= 1 + (float)delta/10.0;
//  oldMouse = modelToScreen( oldMouse );
//  _screenTranslate.set( _screenTranslate.x + (mouseX - oldMouse.x ), _screenTranslate.y + ( mouseY - oldMouse.y ), 0 );
}


///////////////////////////////////
// Setup of GUI controls
///////////////////////////////////
static final int id_main_tab = 1;
static final int id_motor_tab = 2;
static final int id_debug_tab = 3;
static final int id_commport_list = 4;
static final int id_penspeeddown = 5;
static final int id_penspeedup = 6;
static final int id_penpositiondown = 7;
static final int id_penpositionup = 8;
static final int id_penratedown = 9;
static final int id_penrateup = 10;
//static final int id_main_tab = 1;
//static final int id_main_tab = 1;
//-----------------------------------------------------------------------------
void setupGUI()
{
  PVector guiTopLeft = new PVector( 20, height - _guiHeight + 10 );
  int x, y, btnWidth, btnHeight, btnSpacingY, btnSpacingX;

  cp5.getWindow().setPositionOfTabs( (int)guiTopLeft.x, (int)guiTopLeft.y );

  cp5.getTab("default")
    .activateEvent(true)
      .setLabel("main")
        .setId(id_main_tab)
          ;

  cp5.addTab("motor_setup")
    .activateEvent(true)
      .setId(id_motor_tab)
        ;

  cp5.addTab("debug")
    .activateEvent(true)
      .setId(id_debug_tab)
        ;

  // ------------- main (default) menu -------------------------------
  x = (int)guiTopLeft.x + 20;
  y = (int)guiTopLeft.y + 20;
  btnHeight = 20;
  btnWidth = 80; 
  btnSpacingY = btnHeight + 5;
  btnSpacingX = btnWidth + 20;  

  cp5.addButton("btnPlot")
    .setPosition(x, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Plot")
          ;   

  cp5.addButton("btnPlotTime")
    .setPosition(x, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Plot Time")
          ;   
  cp5.addButton("btnResumePlot")
    .setPosition(x, y+btnSpacingY*2)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Resume Plot")
          ;                          
  cp5.addButton("btnPlotStipple")
    .setPosition(x, y+btnSpacingY*3)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Plot Stipple")
          ;                          

  cp5.addButton("btnPlotStippleTime")
    .setPosition(x, y+btnSpacingY*4)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Plot Stipple Time")
          ;                           

  cp5.addButton("btnLoadImage")
    .setPosition(x+btnSpacingX*1, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Load Image")
          ;         

  cp5.addTextfield("txtImagePath")
    .setPosition(x+btnSpacingX*1, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setAutoClear(false)
          ;         

  cp5.addSlider("_imageScale")
    .setPosition(x+btnSpacingX*1, y+btnSpacingY*2)
      .setSize(btnWidth, btnHeight)
        .setRange(0,1)
          .setLabelVisible(true)
            .setCaptionLabel("")
     ;

  cp5.addButton("btnRasterizeImage")
    .setPosition(x+btnSpacingX*1, y+btnSpacingY*3)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Rasterize Image")
          ;
 
   cp5.addSlider("_imageOffsetX")
    .setPosition(x+btnSpacingX*2, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setRange(0,100)
          .setLabelVisible(true)
            .setCaptionLabel("Offset X")
     ;
         
   cp5.addSlider("_imageOffsetY")
    .setPosition(x+btnSpacingX*2, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setRange(0,100)
          .setLabelVisible(true)
            .setCaptionLabel("Offset Y")
     ;
         

  cp5.addToggle("_showImage")
     .setPosition(width-100, (int)guiTopLeft.y+10)
       .setSize(20,20)
         .setCaptionLabel("Show Image")
           .getCaptionLabel().align(ControlP5.LEFT, ControlP5.RIGHT_OUTSIDE).setPaddingX(30)
     ;
    
  cp5.addToggle("_showProcessedImage")
     .setPosition(width-100, (int)guiTopLeft.y+40)
       .setSize(20,20)
         .setCaptionLabel("Show Proc Image")
           .getCaptionLabel().align(ControlP5.LEFT, ControlP5.RIGHT_OUTSIDE).setPaddingX(30)
     ;
          

  //------------------ motor setup menu --------------------
  btnWidth = 60;
  cp5.addButton("btnMoveToHome")
    .setPosition(x, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Move To Home")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnTestPattern")
    .setPosition(x, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Test Pattern")
          .moveTo("motor_setup")
            ;    
  cp5.addButton("btnPenUp")
    .setPosition(x, y+btnSpacingY*2)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Pen Up")
          .moveTo("motor_setup")
            ;   
  cp5.addButton("btnPenDown")
    .setPosition(x, y+btnSpacingY*3)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Pen Down")
          .moveTo("motor_setup")
            ;   
  cp5.addButton("btnVersion")
    .setPosition(x, y+btnSpacingY*4)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Version")
          .moveTo("motor_setup")
            ;   

  cp5.addButton("btnQueryButton")
    .setPosition(x, y+btnSpacingY*5)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("QueryBtn")
          .moveTo("motor_setup")
            ;   

   cp5.addNumberbox("PenSpeedUp",     _motorController._motorSpeedPenUp,   x+btnSpacingX*1, y+0*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penspeedup)
       .setRange(0,100)
         .setMultiplier(1)
           .setDirection(Controller.HORIZONTAL)
             .moveTo("motor_setup")
           ;
   cp5.addNumberbox("PenSpeedDown",   _motorController._motorSpeedPenDown, x+btnSpacingX*1, y+2*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penspeeddown)
       .setRange(0,100)
         .setMultiplier(1)
           .setDirection(Controller.HORIZONTAL)
             .moveTo("motor_setup")
               ;  
   cp5.addNumberbox("PenPositionUp",  _motorController._servoPosUp,        x+btnSpacingX*1, y+4*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penpositionup)
       .setRange(0,100)
         .setMultiplier(1)
           .setDirection(Controller.HORIZONTAL)
             .moveTo("motor_setup")
               ;         
   cp5.addNumberbox("PenPositionDonw",_motorController._servoPosDown,      x+btnSpacingX*2, y+0*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penpositiondown)
       .setRange(0,100).setMultiplier(1)
         .setDirection(Controller.HORIZONTAL)
           .moveTo("motor_setup")
             ;        
   cp5.addNumberbox("PenRateUp",      _motorController._servoRateUp,       x+btnSpacingX*2, y+4*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penrateup).setRange(0,100)
       .setMultiplier(1)
         .setDirection(Controller.HORIZONTAL)
           .moveTo("motor_setup")
             ;         
   cp5.addNumberbox("PenRateDown",    _motorController._servoRateDown,     x+btnSpacingX*2, y+2*btnSpacingY, btnWidth, btnHeight)
     .setId(id_penratedown)
       .setRange(0,100)
         .setMultiplier(1)
           .setDirection(Controller.HORIZONTAL)
             .moveTo("motor_setup")
               ;         


  cp5.addButton("btnInitCommPort")
    .setPosition(x+btnSpacingX*4, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("InitComm")
          .moveTo("motor_setup")
            ;   


  _dlCommPorts = cp5.addDropdownList("commPort")
          .setPosition(x+btnSpacingX*3, y+btnHeight*1)
            .setId(id_commport_list)
              .moveTo("motor_setup")            
                ;

  _dlCommPorts.setBackgroundColor(color(190));
  _dlCommPorts.setItemHeight(btnHeight);
  _dlCommPorts.setBarHeight(btnHeight);
  _dlCommPorts.setWidth(80);
  _dlCommPorts.captionLabel().set("Comm Ports");
  _dlCommPorts.captionLabel().style().marginTop = 5;
  _dlCommPorts.captionLabel().style().marginLeft = 5;

  for (int i=0;i< Serial.list().length;i++) 
  {
    _dlCommPorts.addItem(Serial.list()[i], i);
  }
  _dlCommPorts.setColorActive(color(255, 128));

  x = (int)guiTopLeft.x + 600;
  int buttonSize = 40;

  cp5.addButton("btnMoveUpLeft")
    .setPosition(x+0*buttonSize, y+0*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("\\")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnMoveUp")
    .setPosition(x+1*buttonSize, y+0*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("/\\")
          .moveTo("motor_setup");
  ;
  cp5.addButton("btnMoveUpRight")
    .setPosition(x+2*buttonSize, y+0*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("/")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnMoveLeft")
    .setPosition(x+0*buttonSize, y+1*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("<")
          .moveTo("motor_setup")
            ;
  cp5.addButton("btnMove")
    .setPosition(x+1*buttonSize, y+1*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("O")
          .moveTo("motor_setup")
          ;
  cp5.addButton("btnMoveRight")
    .setPosition(x+2*buttonSize, y+1*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel(">")
          .moveTo("motor_setup")
            ; 

  cp5.addButton("btnMoveDownLeft")
    .setPosition(x+0*buttonSize, y+2*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("/")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnMoveDown")
    .setPosition(x+1*buttonSize, y+2*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("\\/")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnMoveDownRight")
    .setPosition(x+2*buttonSize, y+2*buttonSize)
      .setSize(buttonSize-1, buttonSize-1)
        .setCaptionLabel("\\")
          .moveTo("motor_setup")
            ;
            
  cp5.addSlider("_stepsPerClick")
    .setPosition(x, y+3*buttonSize)
      .setSize(btnWidth, btnHeight)
        .setRange(1,100)
          .setLabelVisible(true)
            .setCaptionLabel("steps")
               .moveTo("motor_setup")
     ;
    
  x = (int)guiTopLeft.x + 500;
  y = height - _guiHeight + 30;
  btnWidth = 80;
  
  cp5.addButton("btnSetUpperLeft")
    .setPosition(x, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Set Upper Left")
          .moveTo("motor_setup")
            ;

  cp5.addButton("btnSetLowerRight")
    .setPosition(x, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Set Lower Right")
          .moveTo("motor_setup")
            ;    

  cp5.addButton("btnSetHome")
    .setPosition(x, y+btnSpacingY*2)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Set Home")
          .moveTo("motor_setup")
            ;    

   
   // ------ setup debug menu -----------------
   
  debugTextarea = cp5.addTextarea("debugtext")
                  .setPosition(100, 100)
                  .setSize(200, 200)
                  .setFont(createFont("", 10))
                  .setLineHeight(14)
                  .setColor(color(200))
                  .setColorBackground(color(0, 100))
                  .setColorForeground(color(255, 100))
                  .moveTo("debug");

  //debugConsole = cp5.addConsole(debugTextarea);//

  x = (int)guiTopLeft.x + 20;
  y = (int)guiTopLeft.y + 20;
  btnWidth = 100;

  cp5.addButton("btnEnableLog")
    .setPosition(x, y+btnSpacingY*0)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Enable Logging")
          .moveTo("debug")
            ;

  cp5.addButton("btnDisableLog")
    .setPosition(x, y+btnSpacingY*1)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Disable Logging")
          .moveTo("debug")
            ;    
  cp5.addButton("btnShowLog")
    .setPosition(x, y+btnSpacingY*2)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Show Log Output")
          .moveTo("debug")
            ;   
  cp5.addButton("btnHideLog")
    .setPosition(x, y+btnSpacingY*3)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Hide Log Output")
          .moveTo("debug")
            ;   
  cp5.addButton("btnClearLog")
    .setPosition(x, y+btnSpacingY*4)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Clear Log")
          .moveTo("debug")
            ;   

  cp5.addButton("btnSaveLog")
    .setPosition(x, y+btnSpacingY*5)
      .setSize(btnWidth, btnHeight)
        .setCaptionLabel("Save Log")
          .moveTo("debug")
            ;   
              
}

//-----------------------------------------------------------------------------
public void controlEvent(ControlEvent theEvent) 
{
  //println("got a control event from controller with id "+theEvent.getId());
   switch(theEvent.getId()) 
   {
     case(id_main_tab): // numberboxA is registered with id 1
       //myColorRect = (int)(theEvent.getController().getValue());
       //println("EVENT 1");
       break;
     case(id_motor_tab):  // 
       //myColorBackground = (int)(theEvent.getController().getValue());
       //println("EVENT 2");
       break;
     case(id_debug_tab):  // 
       //myColorBackground = (int)(theEvent.getController().getValue());
       //println("EVENT 2");
       break;
     case(id_commport_list):  // 
       //myColorBackground = (int)(theEvent.getController().getValue());
       //println("EVENT CommPortList");
       commPort = theEvent.getGroup().captionLabel().getText(); 
       //println(commPort);
       break;
     default:
       //println("EVENT " + theEvent.getId());
       break;
   }
}


//void controlEvent(ControlEvent theEvent) { 
//  if (theEvent.isGroup()) { 
//    String listName = theEvent.getName(); 
//    String itemName = theEvent.getGroup().captionLabel().getText(); 
//    if (listName.equals("Team")) { 
//      currentTeam = itemName; 
//    } else if (listName.equals("League")) { 
//      currentLeague = itemName; 
//    } 
//  } 
//} 



//-----------------------------------------------------------------------------
public void ctrlMachineWidth( float theValue ) 
{
  _motorController._machineWidth = theValue;
}


//-----------------------------------------------------------------------------
public void btnPlot(int theValue) 
{
  _motorController.startPlot();

  RPoint[][] shapePoints = _shapeManager.getPointsInPaths( _shapeManager.getPlotShape(), getShapeOrigin() );

  if ( shapePoints == null )
  {
    return;
  }

  for ( int n=0; n<shapePoints.length; n++ )
  {
    RPoint[] points = shapePoints[n];

    // If there are any points
    if (points != null)
    {
      for (int i=0; i<points.length; i++)
      {
        if ( i == 0 )
        {
          _motorController.moveTo( points[i].x, points[i].y );
          _motorController.penDown();
        }
        else
        {
          _motorController.lineTo( points[i].x, points[i].y );
        }
      }
      _motorController.penUp();
    }
  }

  if ( _motorController._stopped )
  {
    println("Plot cancelled by user");
  }

  _motorController.endPlot();
  _motorController.penUp();
  _motorController.moveToHome();
}

//-----------------------------------------------------------------------------
public void btnResumePlot(int theValue) 
{
  _motorController._resumeMode = true;
  btnPlot(0);
  _motorController._resumeMode = false;
}

//-----------------------------------------------------------------------------
public void btnPlotTime(int theValue) 
{
  _motorController.startDryRun();
  btnPlot(0);
  _motorController.endDryRun();
  printDryRunStats();
}


//-----------------------------------------------------------------------------
public void btnPlotStipple( int theValue ) 
{

  _motorController.startPlot();

  RShape sourceShape = _shapeManager.getPlotShape();

  for ( int i=0; i<sourceShape.countChildren(); i++ )
  {
    RShape shp = sourceShape.children[i];

    float w = shp.getWidth();
    float h = shp.getHeight();
    RPoint c = shp.getCenter();
    float r = w / 2.0;
    //println("w="+w);

    _motorController.fillCircle( new PVector( c.x, c.y), r, 0.4 );
    _motorController.penUp();
  }

  if ( _motorController._stopped )
  {
    println("Plot cancelled by user");
  }
  _motorController.endPlot();
  _motorController.penUp();
  _motorController.moveToHome();
}

//-----------------------------------------------------------------------------
public void btnPlotStippleTime(int theValue) 
{
  _motorController.startDryRun();
  btnPlotStipple(0);
  _motorController.endDryRun();
  printDryRunStats();
}

//-----------------------------------------------------------------------------
public void btnLoadImage(int theValue) 
{
  String filePath = cp5.get(Textfield.class,"txtImagePath").getText();
  println("image file path = " + filePath );
  dbLoadImage( filePath );
}

//-----------------------------------------------------------------------------
public void txtImagePath(String theText) 
{
  // automatically receives results from controller input
  println("image file path : "+theText);
  dbLoadImage( theText );
}

//-----------------------------------------------------------------------------
public void dbLoadImage( String filePath )
{
  PImage img; // temp img to see if file loads ok

  if( filePath.length() != 0 )
  {
    img = loadImage( filePath );
    if( null != img )
    {
      _image = img;
      _imageFilePath = filePath;
      println("_imageFilePath = " + _imageFilePath );
    }
  }
}

//-----------------------------------------------------------------------------
public void btnRasterizeImage(int theValue) 
{
  println("rasterize image " + _imageFilePath );
  
  if( null != _image )
  {
    _shapeManager.rasterizeImage( _image, _imageScale );
  }  
}



//------------ BUTTONS ON MOTOR MENU ------------------------------------------
//-----------------------------------------------------------------------------
public void btnMoveToHome(int theValue) 
{
  _motorController.moveToHome();
  
  _lineStart = _motorController.getHome();
  _lineEnd = _lineStart;
}

//-----------------------------------------------------------------------------
public void btnTestPattern0(int theValue) 
{


  float homeX = _motorController.getHome().x;
  float homeY = _motorController.getHome().y;

  float x = homeX + 0;
  float y = homeY + 270;

  _motorController.moveTo( x-20, y );
  _motorController.penDown();        
  _motorController.lineTo( x+20, y );
  _motorController.penUp();
  _motorController.moveToHome();
}

//-----------------------------------------------------------------------------
public void btnTestPattern(int theValue) 
{


  float homeX = _motorController.getHome().x;
  float homeY = _motorController.getHome().y;
  homeY += 10;

  float x, y;

  int i=0;

  float gridSize = 10;
  float cellsX = 14;
  float cellsY = 20;

  float dx = cellsX / 2 * 10;
  for ( i=0; i<=cellsY; i++ )
  {
    y = homeY + i * gridSize;

    _motorController.moveTo( homeX-dx, y );
    _motorController.penDown();        
    _motorController.lineTo( homeX+dx, y );
    _motorController.penUp();
    dx = -dx;
  }

  float dy = cellsY / 2 * 10;
  float y2 = homeY + dy;
  float x2 = homeX - abs(dx);
  for ( i=0; i<=cellsX; i++ )
  {
    x = x2 + i * gridSize;
    _motorController.moveTo( x, y2-dy );
    _motorController.penDown();        
    _motorController.lineTo( x, y2+dy );
    _motorController.penUp();
    dy = -dy;
  }
  _motorController.moveToHome();
}

//-----------------------------------------------------------------------------
public void btnTestPattern2(int theValue) 
{


  float x = _motorController.getHome().x+00;
  float y = _motorController.getHome().y+150;

  float d = 60;
  _motorController.moveTo( x-d, y-d );
  _motorController.penDown();        
  _motorController.lineTo( x+d, y-d );
  _motorController.lineTo( x+d, y+d );
  _motorController.lineTo( x-d, y+d );
  _motorController.lineTo( x-d, y-d );
  _motorController.lineTo( x+d, y+d );
  _motorController.penUp();
  _motorController.moveTo( x+d, y-d );
  _motorController.penDown();
  _motorController.lineTo( x-d, y+d );       
  _motorController.penUp();
  _motorController.moveToHome();
}

//-----------------------------------------------------------------------------
public void btnPenUp(int theValue) 
{     
  _motorController.penUp();
}

//-----------------------------------------------------------------------------
public void btnPenDown(int theValue) 
{     
  _motorController.penDown();
}

//-----------------------------------------------------------------------------
public void btnInitCommPort(int theValue) 
{     
  println(commPort);
  _motorController.init( commPort );
}

//-----------------------------------------------------------------------------
public void btnMoveUpLeft(int theValue) 
{
  println("btnMoveUpLeft");
  _motorController.setupMoveMotors( -_stepsPerClick, 0 );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveUp(int theValue) 
{
  _motorController.setupMoveMotors( -_stepsPerClick, -_stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveUpRight(int theValue) 
{
  _motorController.setupMoveMotors( 0, -_stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveLeft(int theValue) 
{
  _motorController.setupMoveMotors( -_stepsPerClick, _stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveRight(int theValue) 
{
  _motorController.setupMoveMotors( _stepsPerClick, -_stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveDownLeft(int theValue) 
{
  _motorController.setupMoveMotors( 0, _stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveDown(int theValue) 
{
  _motorController.setupMoveMotors( _stepsPerClick, _stepsPerClick );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnMoveDownRight(int theValue) 
{
  _motorController.setupMoveMotors( _stepsPerClick, 0 );
  
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
  //println("currentPosition x,y : "+_lineStart.x+"  "+_lineStart.y);
}

//-----------------------------------------------------------------------------
public void btnVersion(int theValue) 
{
  _motorController.sendCommand("V\r");
}

//-----------------------------------------------------------------------------
public void btnQueryButton(int theValue) 
{
  _motorController.sendCommand("QB\r");
}

//-----------------------------------------------------------------------------
public void btnSetUpperLeft(int theValue) 
{
  _pageUpperLeft = _motorController.getCurrentXY();
  println("upperLeft  x y : "+_pageUpperLeft.x+"  "+_pageUpperLeft.y);
  println("lowerRight x y : "+_pageLowerRight.x+"  "+_pageLowerRight.y);

  if( _pageUpperLeft.x > (_pageLowerRight.x - 10) )
  {
    _pageUpperLeft.x = _pageLowerRight.x - 10;
  }
  if( _pageUpperLeft.y > (_pageLowerRight.y-10) )
  {
    _pageUpperLeft.y = _pageLowerRight.y - 10;
  }
  _pageSize.x = _pageLowerRight.x - _pageUpperLeft.x;
  _pageSize.y = _pageLowerRight.y - _pageUpperLeft.y;
  
  println("pageSize x y : "+_pageSize.x+"  "+_pageSize.y);
}

//-----------------------------------------------------------------------------
public void btnSetLowerRight(int theValue) 
{
  _pageLowerRight = _motorController.getCurrentXY();
  println("upperLeft  x y : "+_pageUpperLeft.x+"  "+_pageUpperLeft.y);
  println("lowerRight x y : "+_pageLowerRight.x+"  "+_pageLowerRight.y);
  if( _pageLowerRight.x < (_pageUpperLeft.x+10) )
  {
    _pageLowerRight.x = _pageUpperLeft.x + 10;
  }
  if( _pageLowerRight.y < (_pageUpperLeft.y+10) )
  {
    _pageLowerRight.y = _pageUpperLeft.y + 10;
  }
  _pageSize.x = _pageLowerRight.x - _pageUpperLeft.x;
  _pageSize.y = _pageLowerRight.y - _pageUpperLeft.y;
  
  println("pageSize x y : "+_pageSize.x+"  "+_pageSize.y);
}

//-----------------------------------------------------------------------------
public void btnSetHome(int theValue) 
{
  _motorController.setHome();
  _lineStart = _motorController.getCurrentXY();
  _lineEnd = _lineStart;
}


//---------------- DEBUG MENU ITEMS -------------------------------------------
//-----------------------------------------------------------------------------
public void btnEnableLog(int theValue) 
{
  // set a global flag'ish to allow writes to the log
}

//-----------------------------------------------------------------------------
public void btnDisableLog(int theValue) 
{
  // set a global flag'ish to dis-allow writes to the log
}

//-----------------------------------------------------------------------------
public void btnShowLog(int theValue) 
{
   debugTextarea.show();
}

//-----------------------------------------------------------------------------
public void btnHideLog(int theValue) 
{
   debugTextarea.hide();
}

//-----------------------------------------------------------------------------
public void btnClearLog(int theValue) 
{
   debugTextarea.clear();
}

//-----------------------------------------------------------------------------
public void btnSaveLog(int theValue) 
{
  // write the log to a log file on disk
}



//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
void printDryRunStats()
{
  println( "pen up distance = " + _motorController._statsPenUpDistance + " mm");
  println( "pen down distance = " + _motorController._statsPenDownDistance + " mm");    
  println( "pen up duration = " + _motorController._statsPenUpDuration / 60000.0 + " minutes");
  println( "pen down duration = " + _motorController._statsPenDownDuration / 60000.0 + " minutes");
  println( "total duration = " + ( _motorController._statsPenUpDuration + _motorController._statsPenDownDuration ) / 60000.0 + " minutes");
}


//-----------------------------------------------------------------------------
void setupGamepad()
{
  /*
    joypad = controllIO.getDevice("SmartJoy PLUS Adapter");
   joypad.printButtons();
   
   joypad.plug(this, "onGamepadL2ButtonPress", ControllIO.ON_PRESS, 4);
   joypad.plug(this, "onGamepadL2ButtonRelease", ControllIO.ON_RELEASE, 4);
   joypad.plug(this, "onGamepadL1ButtonPress", ControllIO.ON_PRESS, 6);
   joypad.plug(this, "onGamepadL1ButtonRelease", ControllIO.ON_RELEASE, 6);
   //joypad.plug(this, "onGamepadDpadMovement", ControllIO.WHILE_PRESS, 12);
   //joypad.plug(this, "onGamepadDpadPress", ControllIO.ON_PRESS, 12);
   joypad.plug(this, "onGamepadDpadRelease", ControllIO.ON_RELEASE, 12);
   */
}     

//-----------------------------------------------------------------------------
void onGamepadL1ButtonPress() 
{
  _motorController.setSetupMoveMotorStepSize( 3200.0 );
}

//-----------------------------------------------------------------------------
void onGamepadL1ButtonRelease() 
{
  _motorController.setSetupMoveMotorStepSize( 16.0 );
}

//-----------------------------------------------------------------------------
void onGamepadL2ButtonPress() 
{
  _motorController.penDown();
}

//-----------------------------------------------------------------------------
void onGamepadL2ButtonRelease() 
{
  _motorController.penUp();
}

//-----------------------------------------------------------------------------
void onGamepadDpadPress(final float x, final float y) 
{
}

//-----------------------------------------------------------------------------
void onGamepadDpadRelease(final float x, final float y) 
{
  onGamepadDpadMovement( x, y );
}

//-----------------------------------------------------------------------------
void onGamepadDpadMovement(final float x, final float y) 
{
  /*
    if ( x<0 && y<0 ) _motorController.setupMoveMotors( -1, 0 );
   else if ( x==0 && y<0 ) _motorController.setupMoveMotors( -1, -1 );
   else if ( x>0 && y<0 ) _motorController.setupMoveMotors( 0, -1 );
   
   else if ( x<0 && y==0 ) _motorController.setupMoveMotors( -1, 1 );
   else if ( x>0 && y==0 ) _motorController.setupMoveMotors( 1, -1 );
   
   else if ( x<0 && y>0 ) _motorController.setupMoveMotors( 0, 1 );
   else if ( x==0 && y>0 ) _motorController.setupMoveMotors( 1, 1 );
   else if ( x>0 && y>0 ) _motorController.setupMoveMotors( 1, 0 );
   */
}


