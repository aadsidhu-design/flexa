# Dual Tracking System Test Checklist

## Handheld Games Testing
- [ ] Fruit Slicer - Pendulum motion tracking works
- [ ] Fruit Slicer - Vertical movement constrained
- [ ] Fan the Flame - Left/right fanning detected
- [ ] Fan the Flame - Flame responds to motion
- [ ] Witch Brew - Circular motion tracking works
- [ ] Witch Brew - Progress increases with circles
- [ ] All handheld games - ARKit 3D tracking active
- [ ] All handheld games - 50Hz sensor sampling

## Camera Games Testing  
- [ ] Balloon Pop - Camera permission requested
- [ ] Balloon Pop - Elbow angle detection works
- [ ] Balloon Pop - Skeleton overlay visible
- [ ] Constellation - Wrist tracking accurate
- [ ] Constellation - Pattern detection works
- [ ] Wall Climbers - Upward motion detection
- [ ] Wall Climbers - Only up counts as reps
- [ ] All camera games - Apple Vision active

## Navigation Testing
- [ ] Results -> Done -> Survey -> Continue -> HOME
- [ ] Results -> Retry -> Survey -> Continue -> INSTRUCTIONS
- [ ] Instant navigation (no gradual transitions)
- [ ] Background cleanup happens properly

## Data Storage Testing
- [ ] Sessions save locally as JSON
- [ ] Sessions upload to Firebase
- [ ] SPARC calculations work for both modes
- [ ] AI analysis requests sent
- [ ] Historical data loads in Progress view

## Performance Testing
- [ ] 60fps gameplay maintained
- [ ] No memory leaks
- [ ] Smooth transitions
- [ ] Services stop properly when games end

