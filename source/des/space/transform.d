module des.space.transform;

public import des.math.linear.vector;
public import des.math.linear.matrix;

import std.math;
import std.exception;
import std.string : format;

///
interface Transform
{
    ///
    mat4 matrix() @property const;

    ///
    protected final static mat4 getMatrix( const(Transform) tr )
    {
        if( tr !is null )
            return tr.matrix;
        return mat4.diag(1);
    }
}

///
class SimpleTransform : Transform
{
protected:
    mat4 mtr; ///

public:
    @property
    {
        ///
        mat4 matrix() const { return mtr; }
        ///
        void matrix( in mat4 m ) { mtr = m; }
    }
}

///
class TransformList : Transform
{
    Transform[] list; ///
    enum Order { DIRECT, REVERSE }
    Order order = Order.DIRECT; ///

    ///
    @property mat4 matrix() const
    {
        mat4 buf;
        if( order == Order.DIRECT )
            foreach( tr; list )
                buf *= tr.matrix;
        else
            foreach_reverse( tr; list )
                buf *= tr.matrix;
        return buf;
    }
}

///
class CachedTransform : Transform
{
protected:
    mat4 mtr; ///
    Transform transform_source; ///

public:

    ///
    this( Transform ntr ) { setTransform( ntr ); }

    ///
    void setTransform( Transform ntr )
    {
        transform_source = ntr;
        recalc();
    }

    ///
    void recalc()
    {
        if( transform_source !is null )
            mtr = transform_source.matrix;
        else mtr = mat4.diag(1);
    }

    ///
    @property mat4 matrix() const { return mtr; }
}

///
class LookAtTransform : Transform
{
    ///
    vec3 pos=vec3(0), target=vec3(0), up=vec3(0,0,1);

    ///
    @property mat4 matrix() const
    { return calcLookAt( pos, target, up ); }
}

///
class ViewTransform : Transform
{
protected:

    float _ratio = 4.0f / 3.0f;
    float _near = 1e-1;
    float _far = 1e5;

    mat4 self_mtr;

    ///
    abstract void recalc();

    invariant()
    {
        assert( _ratio > 0 );
        assert( 0 < _near && _near < _far );
        assert( !!self_mtr );
    }

public:

    enum MAX_RATIO = 65536;

    @property
    {
        ///
        float ratio() const { return _ratio; }
        ///
        float ratio( float v )
        {
            checkLimit( 1.0f / MAX_RATIO, v, MAX_RATIO, "min ratio", "ratio value", "max ratio" );
            _ratio = v;
            recalc();
            return v;
        }

        ///
        float near() const { return _near; }
        ///
        float near( float v )
        {
            checkLimit( 0, v, _far, "zero", "near value", "far value" );
            _near = v;
            recalc();
            return v;
        }

        ///
        float far() const { return _far; }
        ///
        float far( float v )
        {
            checkLimit( _near, v, float.max, "near value", "far value", "float.max" );
            enforce( v > _near );
            _far = v;
            recalc();
            return v;
        }

        ///
        mat4 matrix() const { return self_mtr; }
    }

protected:

    final void checkLimit(string file=__FILE__,size_t line=__LINE__)
        ( float min_value, float value, float max_value,
          string min_name, string name, string max_name ) const
    {
        enforce( min_value < value, new Exception( format( "%s (%s) less that %s (%s)",
                                                           name, value, min_name, min_value ),
                                                   file, line ) );

        enforce( value < max_value, new Exception( format( "%s (%s) more that %s (%s)",
                                                           name, value, max_name, max_value ),
                                                   file, line ) );
    }
}

///
class PerspectiveTransform : ViewTransform
{
protected:
    float _fov = 70;

    override void recalc() { self_mtr = calcPerspective( _fov, _ratio, _near, _far ); }

    invariant() { assert( _fov > 0 ); }

public:

    enum MIN_FOV = 1e-5;
    enum MAX_FOV = 180 - MIN_FOV;

    @property
    {
        ///
        float fov() const { return _fov; }
        ///
        float fov( float v )
        {
            checkLimit( MIN_FOV, v, MAX_FOV, "min fov", "fov value", "max fov" );
            _fov = v;
            recalc();
            return v;
        }
    }
}

///
class OrthoTransform : ViewTransform
{
protected:

    float _scale = 1;

    invariant() { assert( _scale > 0 ); }

    override void recalc()
    {
        auto s = 1.0 / _scale;
        auto r = s * _ratio;
        auto z = -2.0f / ( _far - _near );
        auto o = -( _far + _near ) / ( _far - _near );

        self_mtr = mat4( s, 0, 0, 0,
                         0, r, 0, 0,
                         0, 0, z, o,
                         0, 0, 0, 1 );
    }

public:

    @property
    {
        ///
        float scale() const { return _scale; }
        ///
        float scale( float v )
        {
            checkLimit( 0, v, float.max, "zero", "scale value", "float.max" );
            _scale = v;
            recalc();
            return v;
        }
    }
}

private:

mat4 calcLookAt( in vec3 pos, in vec3 trg, in vec3 up )
in {
    assert( !!pos );
    assert( !!trg );
    assert( !!up );
}
out(mtr) { assert( !!mtr ); }
body {
    auto z = (pos-trg).e;
    auto x = cross(up,z).e;
    vec3 y;
    if( x ) y = cross(z,x).e;
    else
    {
        y = cross(z,vec3(1,0,0)).e;
        x = cross(y,z).e;
    }
    return mat4( x.x, y.x, z.x, pos.x,
                 x.y, y.y, z.y, pos.y,
                 x.z, y.z, z.z, pos.z,
                   0,   0,   0,     1 );
}

mat4 calcPerspective( float fov_degree, float ratio, float znear, float zfar )
in {
    assert( fov_degree > 0 );
    assert( ratio > 0 );
    assert( znear !is float.nan );
    assert( zfar !is float.nan );
}
out(mtr) { assert( !!mtr ); }
body {
                        /+ fov conv to radians and div 2 +/
    float h = 1.0 / tan( fov_degree * PI / 360.0 );
    float w = h / ratio;

    float depth = znear - zfar;
    float q = ( znear + zfar ) / depth;
    float n = ( 2.0f * znear * zfar ) / depth;

    return mat4( w, 0,  0, 0,
                 0, h,  0, 0,
                 0, 0,  q, n,
                 0, 0, -1, 0 );
}

mat4 calcOrtho( float w, float h, float znear, float zfar )
in {
    assert( w > 0 );
    assert( h > 0 );
    assert( znear !is float.nan );
    assert( zfar !is float.nan );
}
out(mtr) { assert( !!mtr ); }
body {
    float x = znear - zfar;
    return mat4( 2/w, 0,   0,       0,
                 0,   2/h, 0,       0,
                 0,   0,  -1/x,     0,
                 0,   0,   znear/x, 1 );
}
