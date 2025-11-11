-------------------------
-- Donkey Kong Moveset --
-------------------------

if not charSelect then return end

local DONKEY_KONG_ROLL_SPEED = 50
local DONKEY_KONG_ROLL_TIME = 15

--- @param m MarioState
--- Applies gravity to donkey kong
function apply_donkey_kong_gravity(m)
    if m.action == ACT_TWIRLING and m.vel.y < 0.0 then
        apply_twirl_gravity(m)
    elseif m.action == ACT_SHOT_FROM_CANNON then
        m.vel.y = math.max(-75, m.vel.y - 1.5)
    elseif m.action == ACT_LONG_JUMP or m.action == ACT_SLIDE_KICK or m.action == ACT_BBH_ENTER_SPIN then
        m.vel.y = math.max(-75, m.vel.y - 3.0)
    elseif m.action == ACT_LAVA_BOOST or m.action == ACT_FALL_AFTER_STAR_GRAB then
        m.vel.y = math.max(-65, m.vel.y - 4.8)
    elseif m.action == ACT_GETTING_BLOWN then
        m.vel.y = math.max(-75, m.vel.y - (1.5 * m.unkC4))
    elseif should_strengthen_gravity_for_jump_ascent(m) ~= 0 then
        m.vel.y = m.vel.y / 4.0
    elseif m.action & ACT_FLAG_METAL_WATER ~= 0 then
        m.vel.y = math.max(-16, m.vel.y - 2.4)
    elseif m.flags & MARIO_WING_CAP ~= 0 and m.vel.y < 0.0 and m.input & INPUT_A_DOWN ~= 0 then
        m.marioBodyState.wingFlutter = 1

        m.vel.y = m.vel.y - 3.0
        if m.vel.y < -37.5 then
            m.vel.y = math.min(-37.5, m.vel.y + 4)
        end
    else
        if m.vel.y < 0 then
            m.vel.y = math.max(-75, m.vel.y - 6)
        else
            m.vel.y = math.max(-75, m.vel.y - 4.25)
        end
    end
end

--- @param m MarioState
--- @param stepArg integer
--- @return integer
--- Performs an air step for donkey kong
--- TODO: this prevents DK from ledge grabbing. Is this fixable?
function perform_donkey_kong_air_step(m, stepArg)
    local intendedPos = gVec3fZero()
    local quarterStepResult
    local stepResult = AIR_STEP_NONE

    m.wall = nil

    for i = 0, 4 do
        local step = gVec3fZero()
        step = {
            x = m.vel.x / 4.0,
            y = m.vel.y / 4.0,
            z = m.vel.z / 4.0,
        }

        intendedPos.x = m.pos.x + step.x
        intendedPos.y = m.pos.y + step.y
        intendedPos.z = m.pos.z + step.z

        vec3f_normalize(step)
        set_find_wall_direction(step, true, true)

        quarterStepResult = perform_air_quarter_step(m, intendedPos, stepArg)
        set_find_wall_direction(step, false, false)

        --! On one qf, hit OOB/ceil/wall to store the 2 return value, and continue
        -- getting 0s until your last qf. Graze a wall on your last qf, and it will
        -- return the stored 2 with a sharply angled reference wall. (some gwks)

        if (quarterStepResult ~= AIR_STEP_NONE) then
            stepResult = quarterStepResult
        end

        if (quarterStepResult == AIR_STEP_LANDED or quarterStepResult == AIR_STEP_GRABBED_LEDGE
                or quarterStepResult == AIR_STEP_GRABBED_CEILING
                or quarterStepResult == AIR_STEP_HIT_LAVA_WALL) then
            break
        end
    end

    if (m.vel.y >= 0.0) then
        m.peakHeight = m.pos.y
    end

    m.terrainSoundAddend = mario_get_terrain_sound_addend(m)

    if (m.action ~= ACT_FLYING and m.action ~= ACT_BUBBLED) then
        apply_donkey_kong_gravity(m)
    end
    apply_vertical_wind(m)

    vec3f_copy(m.marioObj.header.gfx.pos, m.pos)
    vec3s_set(m.marioObj.header.gfx.angle, 0, m.faceAngle.y, 0)

    return stepResult
end

function before_donkey_kong_phys_step(m, stepType, stepArg)
    if stepType == STEP_TYPE_GROUND then
        -- return perform_donkey_kong_ground_step(m) -- TBA
    elseif stepType == STEP_TYPE_AIR then
        return perform_donkey_kong_air_step(m, stepArg)
    elseif stepType == STEP_TYPE_WATER then
        -- return perform_donkey_kong_water_step(m) -- TBA
    elseif stepType == STEP_TYPE_HANG then
        -- return perform_donkey_kong_hanging_step(m) -- TBA
    end
end

function donkey_kong_before_action(m, action)
    if (action == ACT_DIVE or action == ACT_MOVE_PUNCHING) and m.action & ACT_FLAG_AIR == 0 and m.forwardVel > 20 then
        mario_set_forward_vel(m, math.min(m.forwardVel - 32 + DONKEY_KONG_ROLL_SPEED, DONKEY_KONG_ROLL_SPEED))
        m.vel.y = 20
        return ACT_DONKEY_KONG_ROLL
    end
end

function on_attack_object(m, o, interaction)
    -- speed up when hitting enemies with roll
    if (m.action == ACT_DONKEY_KONG_ROLL or m.action == ACT_DONKEY_KONG_ROLL_AIR) and (interaction & INT_FAST_ATTACK_OR_SHELL ~= 0) then
        if o.oInteractType == INTERACT_BULLY then
            mario_set_forward_vel(m, 0)
            m.actionTimer = DONKEY_KONG_ROLL_TIME
            m.actionArg = 1
        else
            local newForwardVel = math.min(m.forwardVel * 1.1, 70)
            mario_set_forward_vel(m, newForwardVel)
            m.actionTimer = 0
            m.actionArg = 0
        end
    end
end
hook_event(HOOK_ON_ATTACK_OBJECT, on_attack_object)

_G.ACT_DONKEY_KONG_ROLL = allocate_mario_action(ACT_GROUP_MOVING | ACT_FLAG_MOVING)
_G.ACT_DONKEY_KONG_ROLL_AIR = allocate_mario_action(ACT_GROUP_AIRBORNE | ACT_FLAG_AIR | ACT_FLAG_ALLOW_VERTICAL_WIND_ACTION)

---@param m MarioState
local function act_donkey_kong_roll(m)
    if (not m) then return 0 end

    if (should_begin_sliding(m)) ~= 0 then
        return set_mario_action(m, ACT_BEGIN_SLIDING, 0)
    end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        local result = set_jumping_action(m, ACT_JUMP, 0)
        m.forwardVel = m.forwardVel / 0.8
        return result
    end

    m.actionTimer = m.actionTimer + 1
    if m.actionTimer > DONKEY_KONG_ROLL_TIME and m.actionArg ~= 0 then
        -- ending animation
        local newForwardVel = approach_s32(m.forwardVel, 0, 5, 5)
        mario_set_forward_vel(m, newForwardVel)
        set_mario_animation(m, MARIO_ANIM_STOP_SKID)
        set_anim_to_frame(m, m.marioObj.header.gfx.animInfo.animFrame + 2)
        if is_anim_at_end(m) ~= 0 then
            m.actionArg = 0
        end
    elseif set_mario_anim_with_accel(m, MARIO_ANIM_FORWARD_SPINNING, m.forwardVel * 0x1000) == 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
    end

    local result = perform_ground_step(m)
    if result == GROUND_STEP_LEFT_GROUND then
        --mario_set_forward_vel(m, DONKEY_KONG_ROLL_SPEED)
        return set_mario_action(m, ACT_DONKEY_KONG_ROLL_AIR, 0)
    elseif result == GROUND_STEP_HIT_WALL then
        if (m.wall or gServerSettings.bouncyLevelBounds == BOUNCY_LEVEL_BOUNDS_OFF) then
            set_mario_particle_flags(m, PARTICLE_VERTICAL_STAR, 0);
            slide_bonk(m, ACT_GROUND_BONK, ACT_WALKING)
            return
        end
    end

    -- end roll earlier from falls and after hitting an enemy
    if m.actionTimer > DONKEY_KONG_ROLL_TIME and m.actionArg == 0 then
        return set_mario_action(m, ACT_WALKING, 0)
    end

    return 0
end

hook_mario_action(ACT_DONKEY_KONG_ROLL, { every_frame = act_donkey_kong_roll }, INT_FAST_ATTACK_OR_SHELL)

---@param m MarioState
local function act_donkey_kong_roll_air(m)
    if (not m) then return 0 end

    if (m.input & INPUT_A_PRESSED) ~= 0 then
        m.terrainSoundAddend = 0
        local result = set_mario_action(m, ACT_JUMP, 0)
        m.forwardVel = m.forwardVel / 0.8
        return result
    end

    m.actionTimer = m.actionTimer + 1
    if set_mario_anim_with_accel(m, MARIO_ANIM_FORWARD_SPINNING, m.forwardVel * 0x1000) == 0 then
        play_sound(SOUND_ACTION_SPIN, m.marioObj.header.gfx.cameraToObject)
    end

    local result = perform_air_step(m, AIR_STEP_CHECK_LEDGE_GRAB)
    if result == AIR_STEP_LANDED then
        if (should_get_stuck_in_ground(m) ~= 0) then
            queue_rumble_data_mario(m, 5, 80);
            play_character_sound(m, CHAR_SOUND_OOOF2);
            set_mario_particle_flags(m, PARTICLE_MIST_CIRCLE, 0);
            drop_and_set_mario_action(m, ACT_HEAD_STUCK_IN_GROUND, 0);
        elseif (check_fall_damage(m, ACT_HARD_FORWARD_GROUND_KB) ~= 0) then
            set_mario_action(m, ACT_DONKEY_KONG_ROLL, 0);
        end
    elseif result == AIR_STEP_HIT_WALL then
        if (m.wall or gServerSettings.bouncyLevelBounds == BOUNCY_LEVEL_BOUNDS_OFF) then
            mario_bonk_reflection(m, 1);
            if (m.vel.y > 0) then m.vel.y = 0 end

            set_mario_particle_flags(m, PARTICLE_VERTICAL_STAR, 0);
            drop_and_set_mario_action(m, ACT_BACKWARD_AIR_KB, 0);
            return 1
        end
    elseif result == AIR_STEP_HIT_LAVA_WALL then
        lava_boost_on_wall(m)
        return 1
    end

    if m.actionTimer > DONKEY_KONG_ROLL_TIME then
        return set_mario_action(m, ACT_FREEFALL, 0)
    end

    return 0
end

hook_mario_action(ACT_DONKEY_KONG_ROLL_AIR, { every_frame = act_donkey_kong_roll_air }, INT_FAST_ATTACK_OR_SHELL)