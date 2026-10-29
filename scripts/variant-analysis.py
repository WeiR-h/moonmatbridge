"""Independent byte evidence for the four fixed Octave 8.4 producer variants."""
from pathlib import Path
import hashlib,json,struct,zlib

def element(data,offset):
    word,size=struct.unpack_from('<II',data,offset)
    if word>>16: return word&65535,word>>16,offset+4,offset+8
    return word,size,offset+8,offset+8+size+(-size)%8

def analyze(path):
    data=path.read_bytes()
    kind,size,start,end=element(data,128)
    matrix=zlib.decompress(data[start:start+size]) if kind==15 else data[128:]
    kind,declared=struct.unpack_from('<II',matrix)
    assert kind==14
    _,_,flags,pos=element(matrix,8)
    bits,reserved=struct.unpack_from('<II',matrix,flags)
    _,n,dims,pos=element(matrix,pos)
    shape=list(struct.unpack_from('<'+'i'*(n//4),matrix,dims))
    _,n,name,pos=element(matrix,pos)
    label=matrix[name:name+n].decode('ascii')
    evidence={'declared_body_bytes':declared,'actual_body_bytes':len(matrix)-8,'class_id':bits&255,'logical':bool(bits&512),'second_flags_word':reserved,'shape':shape,'name':label}
    if label=='small_char_matrix':
        assert bits&255==4 and declared==len(matrix)-8+4
        k,n,start,end=element(matrix,pos)
        assert k==16 and n==4 and end==len(matrix)
        evidence['violation']='miMATRIX declares four more body bytes than are present; small UTF8 element itself is complete.'
        evidence['format_section']='MAT-File Format: Data Element Format / Number of Bytes'
    elif label=='sparse_logical':
        assert bits&255==9 and bits&512 and declared==len(matrix)-8
        tags=[]
        for _ in range(3):
            k,n,start,pos=element(matrix,pos);tags.append([k,n])
        assert tags==[[5,8],[5,16],[9,16]] and pos==len(matrix)
        evidence['payload_tags']=tags
        evidence['violation']='mxUINT8 logical dense class has CSC ir/jc/value subelements and a capacity word; this is not a valid dense payload or mxSPARSE class.'
        evidence['format_section']='MAT-File Format: Array Flags Class / Sparse Array Subelements'
    else: raise AssertionError('Unclassified producer case: '+label)
    return {'file':path.name,'sha256':hashlib.sha256(data).hexdigest(),'classification':'nonconforming_producer_variant','evidence':evidence,'reference':'https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf','producer_source':'https://github.com/gnu-octave/octave/blob/release-8-4-0/libinterp/corefcn/ls-mat5.cc'}

def main():
    root=Path(__file__).resolve().parents[1]
    version=json.loads((root/'package.json').read_bytes())['version']
    cases=[analyze(p) for p in sorted((root/'examples/octave/variants').glob('producer-*.mat'))]
    assert len(cases)==4
    report={'status':'classified','version':version,'cases':cases,'scope':'Independent length/class evidence for fixed fixture hashes. Octave/SciPy consumption remains recorded separately; accepting malformed input is not standard conformance.'}
    (root/f'verification/reports/producer-variants-v{version}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'classified','cases':len(cases)}))

if __name__=='__main__':main()
