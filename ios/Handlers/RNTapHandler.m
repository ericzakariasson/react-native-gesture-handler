//
//  RNTapHandler.m
//  RNGestureHandler
//
//  Created by Krzysztof Magiera on 12/10/2017.
//  Copyright © 2017 Software Mansion. All rights reserved.
//

#import "RNTapHandler.h"

#import <UIKit/UIGestureRecognizerSubclass.h>

#import <React/RCTConvert.h>

// RNBetterTapGestureRecognizer extends UIGestureRecognizer instead of UITapGestureRecognizer 
// because the latter does not allow for parameters like maxDelay, maxDuration, minPointers, 
// maxDelta to be configured. Using our custom implementation of tap recognizer we are able
// to support these.

@interface RNBetterTapGestureRecognizer : UIGestureRecognizer

@property (nonatomic) NSUInteger numberOfTaps;
@property (nonatomic) NSTimeInterval maxDelay;
@property (nonatomic) NSTimeInterval maxDuration;
@property (nonatomic) CGFloat maxDistSq;
@property (nonatomic) CGFloat maxDeltaX;
@property (nonatomic) CGFloat maxDeltaY;
@property (nonatomic) NSInteger minPointers;
@property (nonatomic) CGFloat touchRadius;

- (id)initWithGestureHandler:(RNGestureHandler*)gestureHandler;

@end

@implementation RNBetterTapGestureRecognizer {
  __weak RNGestureHandler *_gestureHandler;
  NSUInteger _tapsSoFar;
  CGPoint _initPosition;
  NSInteger _maxNumberOfTouches;
  CGFloat _touchRadius;
}

- (id)initWithGestureHandler:(RNGestureHandler*)gestureHandler
{
  if ((self = [super initWithTarget:gestureHandler action:@selector(handleGesture:)])) {
    _gestureHandler = gestureHandler;
    _tapsSoFar = 0;
    _numberOfTaps = 1;
    _minPointers = 1;
    _maxDelay = 0.2;
    _maxDuration = NAN;
    _maxDeltaX = NAN;
    _maxDeltaY = NAN;
    _maxDistSq = NAN;
    _touchRadius = NAN;
  }
  return self;
}

- (void)triggerAction
{
  [_gestureHandler handleGesture:self];
}

- (void)cancel
{
  self.enabled = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesBegan:touches withEvent:event];
  if (_tapsSoFar == 0) {
    _initPosition = [self locationInView:self.view];
  }
  _tapsSoFar++;
  if (_tapsSoFar) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(cancel) object:nil];
  }
    
  UITouch *touch = [touches anyObject];
  _touchRadius = touch.majorRadius;
      
  [self _beginObservingTouchMajorRadius:touch];
    
  NSInteger numberOfTouches = [touches count];
  if (numberOfTouches > _maxNumberOfTouches) {
    _maxNumberOfTouches = numberOfTouches;
  }
  if (!isnan(_maxDuration)) {
    [self performSelector:@selector(cancel) withObject:nil afterDelay:_maxDuration];
  }
  self.state = UIGestureRecognizerStatePossible;
  [self triggerAction];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesMoved:touches withEvent:event];
  NSInteger numberOfTouches = [touches count];
  if (numberOfTouches > _maxNumberOfTouches) {
    _maxNumberOfTouches = numberOfTouches;
  }
  
  if (self.state != UIGestureRecognizerStatePossible) {
    return;
  }
  
  if ([self shouldFailUnderCustomCriteria]) {
    UITouch *touch = [touches anyObject];
    [self _endObservingTouchMajorRadius:touch];
      
    self.state = UIGestureRecognizerStateFailed;
    [self triggerAction];
    [self reset];
    return;
  }
  
  self.state = UIGestureRecognizerStatePossible;
  [self triggerAction];
}

- (void)_beginObservingTouchMajorRadius:(UITouch *)touch {
  // Observe UITouch -majorRadius changes.
  [touch addObserver:self
          forKeyPath:NSStringFromSelector(@selector(majorRadius))
             options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
             context:NULL];
}

- (void)_endObservingTouchMajorRadius:(UITouch *)touch {
  @try {
    [touch removeObserver:self
               forKeyPath:NSStringFromSelector(@selector(majorRadius))
                  context:NULL];
  } @catch (NSException *e) { }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
  // Anytime -majorRadius changes, indicate that the gesture's state has changed.
  if ([keyPath isEqualToString:NSStringFromSelector(@selector(majorRadius))]) {
    self.state = UIGestureRecognizerStateChanged;
    _touchRadius = [(UITouch *)object majorRadius];
  }
}

- (CGPoint)translationInView {
  CGPoint currentPosition = [self locationInView:self.view];
  return CGPointMake(currentPosition.x - _initPosition.x, currentPosition.y - _initPosition.y);
}

- (BOOL)shouldFailUnderCustomCriteria
{
  if (_gestureHandler.shouldCancelWhenOutside) {
    if (![_gestureHandler containsPointInView]) {
      return YES;
    }
  }
  
  CGPoint trans = [self translationInView];
  if (TEST_MAX_IF_NOT_NAN(fabs(trans.x), _maxDeltaX)) {
    return YES;
  }
  if (TEST_MAX_IF_NOT_NAN(fabs(trans.y), _maxDeltaY)) {
    return YES;
  }
  if (TEST_MAX_IF_NOT_NAN(fabs(trans.y * trans.y + trans.x + trans.x), _maxDistSq)) {
    return YES;
  }
  return NO;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesEnded:touches withEvent:event];
  if (_numberOfTaps == _tapsSoFar && _maxNumberOfTouches >= _minPointers) {
    self.state = UIGestureRecognizerStateEnded;
    UITouch *touch = [touches anyObject];
    [self _endObservingTouchMajorRadius:touch];
    [self reset];
  } else {
    [self performSelector:@selector(cancel) withObject:nil afterDelay:_maxDelay];
  }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesCancelled:touches withEvent:event];
    
  UITouch *touch = [touches anyObject];
  [self _endObservingTouchMajorRadius:touch];
  
  self.state = UIGestureRecognizerStateCancelled;
  [self reset];
}

- (void)reset
{
  if (self.state == UIGestureRecognizerStateFailed) {
    [self triggerAction];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(cancel) object:nil];
  _tapsSoFar = 0;
  _maxNumberOfTouches = 0;
  self.enabled = YES;
  [super reset];
}

@end

@implementation RNTapGestureHandler {
    RNGestureHandlerEventExtraData * _lastData;
}

- (instancetype)initWithTag:(NSNumber *)tag
{
  if ((self = [super initWithTag:tag])) {
    _recognizer = [[RNBetterTapGestureRecognizer alloc] initWithGestureHandler:self];
  }
  return self;
}

- (void)configure:(NSDictionary *)config
{
  [super configure:config];
  RNBetterTapGestureRecognizer *recognizer = (RNBetterTapGestureRecognizer *)_recognizer;
  
  APPLY_INT_PROP(numberOfTaps);
  APPLY_INT_PROP(minPointers);
  APPLY_FLOAT_PROP(maxDeltaX);
  APPLY_FLOAT_PROP(maxDeltaY);
  APPLY_FLOAT_PROP(touchRadius);
  
  id prop = config[@"maxDelayMs"];
  if (prop != nil) {
    recognizer.maxDelay = [RCTConvert CGFloat:prop] / 1000.0;
  }
  
  prop = config[@"maxDurationMs"];
  if (prop != nil) {
    recognizer.maxDuration = [RCTConvert CGFloat:prop] / 1000.0;
  }
  
  prop = config[@"maxDist"];
  if (prop != nil) {
    CGFloat dist = [RCTConvert CGFloat:prop];
    recognizer.maxDistSq = dist * dist;
  }
}

- (RNGestureHandlerEventExtraData *)eventExtraData:(RNBetterTapGestureRecognizer *)recognizer{
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        return _lastData;
    }
    
    _lastData = [RNGestureHandlerEventExtraData
                 forPosition:[recognizer locationInView:recognizer.view]
                 withAbsolutePosition:[recognizer locationInView:recognizer.view.window]
                 withNumberOfTouches:recognizer.numberOfTouches
                 withTouchRadius: recognizer.touchRadius];
    
    return _lastData;
}

@end

